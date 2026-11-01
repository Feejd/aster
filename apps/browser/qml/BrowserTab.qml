pragma ComponentBehavior: Bound
import QtQuick
import QtWebEngine
import Aster.Ui
import Aster.Browser

// Jedna karta: strona (WebEngineView), strona startowa albo strona wewnętrzna (Historia, Pobrane, Ustawienia).
// Karta przywrócona z sesji wczytuje się dopiero, gdy pierwszy raz stanie się widoczna.
// Wszystko, co dzieje się na stronie, a dotyczy tylko tej karty (okna strony, błąd certyfikatu,
// awaria procesu strony, narzędzia dewelopera), jest obsługiwane tutaj.
Item {
    id: tab
    required property WebEngineProfile profile
    property string initialUrl
    property bool lazy: false              // wczytaj dopiero przy pierwszym pokazaniu
    property bool adopted: false           // karta na okno otwierane przez stronę (bez strony startowej)
    property bool privateMode: false

    readonly property alias view: web
    property string internal: ""           // history | downloads | settings
    readonly property string pageUrl: internal ? "aster://" + internal : web.url.toString()
    readonly property bool blank: !internal && !adopted && (web.url.toString() === "" || web.url.toString() === "about:blank")
    readonly property string pageTitle: internal ? Urls.pages[internal]
                                        : blank ? "Nowa karta"
                                        : (web.title || Urls.host(pageUrl) || "Wczytywanie…")
    readonly property string pageIcon: internal || blank ? "" : web.icon.toString()
    readonly property bool secure: pageUrl.indexOf("https://") === 0
    readonly property bool insecure: pageUrl.indexOf("http://") === 0
    readonly property bool loading: !internal && web.loading
    readonly property bool canGoBack: internal ? web.url.toString() !== "" : web.canGoBack
    property color themeColor: "transparent"
    property int blocked: 0                // zablokowane elementy śledzące na tej stronie
    property bool crashed: false
    property var certError: null
    property var dialog: null
    property bool devTools: false
    property string hoveredLink: ""
    property bool started: false

    signal visited(string url, string title)
    signal permissionAsked(var permission)
    signal newWindow(var request)
    signal fullScreen(var request)
    signal contextMenu(var request)
    signal findResult(int active, int total)
    signal openRequested(string url, bool background)
    signal closeRequested()

    function begin() {
        if (started) return;
        started = true;
        if (initialUrl) load(initialUrl);
    }
    Component.onCompleted: if (!lazy || visible) begin()
    onVisibleChanged: if (visible) begin()

    function load(url) {
        started = true;
        const page = Urls.internal(url);
        if (page) { internal = page; return; }
        internal = "";
        crashed = false;
        web.url = url;
    }
    function goBack() { if (internal) internal = ""; else web.goBack(); }
    function reload() { crashed = false; if (!internal) web.reload(); }

    // Kolor motywu strony (np. czerwień YouTube) — tylko prawidłowe zapisy kolorów
    function readThemeColor() {
        web.runJavaScript("(function(){var m=document.querySelector('meta[name=\"theme-color\"]');return m?m.content:'';})()",
                          function (c) {
                              c = (c || "").trim();
                              tab.themeColor = /^#([0-9a-f]{3}|[0-9a-f]{6})$/i.test(c) || /^rgba?\(/i.test(c) ? c : "transparent";
                          });
    }

    Connections {
        target: Browser
        function onTrackerBlocked(site) { if (!tab.internal && site === Browser.siteOf(tab.pageUrl)) tab.blocked++; }
    }

    // ——— Strona ———
    Item {
        id: pageArea
        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
        width: tab.devTools ? parent.width * 0.58 : parent.width
        visible: !tab.blank && !tab.internal

        WebEngineView {
            id: web
            anchors.fill: parent
            profile: tab.profile
            backgroundColor: Theme.dark ? "#0E0F13" : "white"
            settings.fullScreenSupportEnabled: true
            settings.scrollAnimatorEnabled: true
            settings.focusOnNavigationEnabled: true
            settings.pdfViewerEnabled: true
            settings.pluginsEnabled: true
            settings.dnsPrefetchEnabled: true
            settings.screenCaptureEnabled: true
            settings.playbackRequiresUserGesture: false
            settings.javascriptCanOpenWindows: true
            settings.javascriptCanAccessClipboard: true
            settings.javascriptCanPaste: true
            settings.forceDarkMode: Browser.forceDark

            onLoadingChanged: (info) => {
                if (info.status === WebEngineView.LoadStartedStatus) {
                    tab.themeColor = "transparent";
                    tab.blocked = 0;
                    tab.crashed = false;
                    if (!tab.privateMode) web.zoomFactor = Browser.zoomFor(info.url.toString());
                } else if (info.status === WebEngineView.LoadSucceededStatus) {
                    tab.readThemeColor();
                    if (!tab.privateMode) tab.visited(info.url.toString(), web.title);
                } else if (info.errorCode === -3 && !web.canGoBack) {
                    // Adres okazał się plikiem do pobrania (przerwana nawigacja, karta bez historii):
                    // karta otwarta przez stronę znika, nowa wraca do strony startowej
                    if (tab.adopted) tab.closeRequested();
                    else web.url = "about:blank";
                }
            }
            onTitleChanged: if (!tab.privateMode && !web.loading) Browser.updateTitle(web.url.toString(), web.title)
            onLinkHovered: (url) => tab.hoveredLink = url.toString()
            onPermissionRequested: (permission) => tab.permissionAsked(permission)
            onNewWindowRequested: (request) => tab.newWindow(request)
            onFullScreenRequested: (request) => tab.fullScreen(request)
            onContextMenuRequested: (request) => { request.accepted = true; tab.contextMenu(request); }
            onFindTextFinished: (result) => tab.findResult(result.activeMatch, result.numberOfMatches)
            onRenderProcessTerminated: (status, code) => {
                if (status !== WebEngineView.NormalTerminationStatus) tab.crashed = true;
            }
            onCertificateError: (error) => {
                error.defer();
                tab.certError = error;
            }
            onJavaScriptDialogRequested: (request) => {
                request.accepted = true;
                dlgInput.text = request.defaultText || "";
                tab.dialog = { kind: "js", request: request };
            }
            onAuthenticationDialogRequested: (request) => {
                request.accepted = true;
                authUser.text = "";
                authPass.text = "";
                tab.dialog = { kind: "auth", request: request };
            }
            // Strona prosi o zamknięcie się (window.close())
            onWindowCloseRequested: tab.closeRequested()
        }

        // Przyciski „wstecz/dalej” myszy
        TapHandler {
            acceptedButtons: Qt.BackButton | Qt.ForwardButton
            onTapped: (point, button) => { if (button === Qt.BackButton) web.goBack(); else web.goForward(); }
        }

        // Adres linku pod kursorem (lewy dolny róg)
        Rectangle {
            id: linkTip
            x: 8; anchors.bottom: parent.bottom; anchors.bottomMargin: 8
            width: Math.min(parent.width * 0.6, linkText.implicitWidth + 18)
            height: 26; radius: 8
            color: Theme.dark ? Qt.rgba(0.12, 0.12, 0.15, 0.96) : Qt.rgba(1, 1, 1, 0.97)
            border.width: 1; border.color: Theme.edge
            opacity: tab.hoveredLink ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
            Text {
                id: linkText
                x: 9; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 18
                text: tab.hoveredLink
                elide: Text.ElideMiddle
                color: Theme.text2
                font.family: Theme.font; font.pixelSize: 12
            }
        }

        // ——— Strona przestała działać ———
        Rectangle {
            anchors.fill: parent
            visible: tab.crashed
            color: Theme.paneGlass
            Column {
                anchors.centerIn: parent
                width: Math.min(420, parent.width - 60)
                spacing: 14
                Rectangle {
                    width: 64; height: 64; radius: 20
                    color: Theme.accentSoft
                    Icon { anchors.centerIn: parent; d: Icons.flame; size: 30; stroke: 2; color: Theme.accentText }
                }
                Text { text: "Ta strona przestała działać"; color: Theme.text; font.family: Theme.font; font.pixelSize: 22; font.weight: Font.DemiBold; font.letterSpacing: -0.4 }
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: "Coś poszło nie tak przy wyświetlaniu „" + Urls.host(tab.pageUrl) + "”. Pozostałe karty działają normalnie."
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 14; lineHeight: 1.2
                }
                PillButton { text: "Odśwież stronę"; primary: true; onClicked: tab.reload() }
            }
        }

        // ——— Niebezpieczne połączenie (błąd certyfikatu) ———
        Rectangle {
            anchors.fill: parent
            visible: !!tab.certError
            color: Theme.paneGlass
            Column {
                anchors.centerIn: parent
                width: Math.min(480, parent.width - 60)
                spacing: 14
                Rectangle {
                    width: 64; height: 64; radius: 20
                    color: Qt.rgba(1, 0.27, 0.23, 0.16)
                    Icon { anchors.centerIn: parent; d: Icons.lock; size: 30; stroke: 2; color: Theme.danger }
                }
                Text { text: "To połączenie nie jest prywatne"; color: Theme.text; font.family: Theme.font; font.pixelSize: 22; font.weight: Font.DemiBold; font.letterSpacing: -0.4 }
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: tab.certError
                          ? "Ktoś może próbować przechwycić dane, które wysyłasz do <b>" + Urls.host(tab.certError.url.toString()) + "</b> (hasła, wiadomości, numery kart). " + tab.certError.description
                          : ""
                    textFormat: Text.StyledText
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 14; lineHeight: 1.2
                }
                Row {
                    spacing: 10
                    PillButton {
                        text: "Wróć w bezpieczne miejsce"; primary: true
                        onClicked: { tab.certError.rejectCertificate(); tab.certError = null; if (web.canGoBack) web.goBack(); }
                    }
                    PillButton {
                        visible: !!tab.certError && tab.certError.overridable
                        text: "Wejdź mimo to"
                        onClicked: { tab.certError.acceptCertificate(); tab.certError = null; }
                    }
                }
            }
        }
    }

    // ——— Narzędzia dewelopera (F12) ———
    Loader {
        active: tab.devTools
        anchors.left: pageArea.right; anchors.right: parent.right
        anchors.top: parent.top; anchors.bottom: parent.bottom
        sourceComponent: Item {
            Rectangle { width: 1; height: parent.height; color: Theme.line; z: 2 }
            WebEngineView {
                anchors.fill: parent
                anchors.leftMargin: 1
                profile: tab.profile
                inspectedView: web
            }
        }
    }

    // ——— Strona startowa i strony wewnętrzne ———
    StartPage {
        anchors.fill: parent
        visible: tab.blank
        privateMode: tab.privateMode
        onOpen: (url, background) => { if (background) tab.openRequested(url, true); else tab.load(url); }
    }
    Loader {
        id: internalPage
        anchors.fill: parent
        active: tab.internal !== ""
        visible: active
        source: tab.internal === "history" ? "HistoryPage.qml" : tab.internal === "downloads" ? "DownloadsPage.qml" : tab.internal === "settings" ? "SettingsPage.qml" : ""
        Connections {
            target: internalPage.item
            ignoreUnknownSignals: true
            function onOpen(url, background) { if (background) tab.openRequested(url, true); else tab.load(url); }
        }
    }

    // ——— Okna strony: alert / confirm / prompt, logowanie HTTP ———
    Rectangle {
        id: dlgLayer
        anchors.fill: parent
        z: 80
        color: Qt.rgba(0, 0, 0, 0.32)
        visible: !!tab.dialog
        MouseArea { anchors.fill: parent }
        function close(ok) {
            const d = tab.dialog;
            if (!d) return;
            tab.dialog = null;
            if (d.kind === "auth") { if (ok) d.request.dialogAccept(authUser.text, authPass.text); else d.request.dialogReject(); }
            else if (ok) d.request.dialogAccept(dlgInput.text);
            else d.request.dialogReject();
            web.forceActiveFocus();
        }
        Rectangle {
            id: dlgBox
            anchors.centerIn: parent
            width: Math.min(440, parent.width - 40)
            height: dlgCol.implicitHeight + 48
            radius: 20
            color: Theme.surface
            border.width: 1; border.color: Theme.edge
            readonly property var req: tab.dialog ? tab.dialog.request : null
            readonly property bool auth: !!tab.dialog && tab.dialog.kind === "auth"
            readonly property int type: !auth && req ? req.type : -1
            Column {
                id: dlgCol
                x: 24; y: 24
                width: parent.width - 48
                spacing: 12
                Text {
                    width: parent.width
                    text: dlgBox.auth ? "Zaloguj się do " + (dlgBox.req ? Urls.host(dlgBox.req.url.toString()) : "")
                                      : (dlgBox.type === JavaScriptDialogRequest.DialogTypeBeforeUnload ? "Opuścić tę stronę?" : "Strona " + Urls.host(tab.pageUrl) + " pisze")
                    elide: Text.ElideRight
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    visible: text !== ""
                    text: dlgBox.auth ? (dlgBox.req && dlgBox.req.realm ? "„" + dlgBox.req.realm + "”" : "")
                                      : (dlgBox.type === JavaScriptDialogRequest.DialogTypeBeforeUnload ? "Zmiany, których nie zapisano, mogą przepaść." : (dlgBox.req ? dlgBox.req.message : ""))
                    wrapMode: Text.Wrap
                    maximumLineCount: 12
                    elide: Text.ElideRight
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 14; lineHeight: 1.15
                }
                Field {
                    id: dlgField
                    visible: dlgBox.type === JavaScriptDialogRequest.DialogTypePrompt
                    TextInput {
                        id: dlgInput
                        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 14
                        clip: true
                        focus: dlgField.visible && tab.dialog !== null
                        Keys.onReturnPressed: dlgLayer.close(true)
                    }
                }
                Field {
                    visible: dlgBox.auth
                    TextInput {
                        id: authUser
                        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 14
                        clip: true
                        focus: dlgBox.auth
                        KeyNavigation.tab: authPass
                        Text { anchors.verticalCenter: parent.verticalCenter; visible: !authUser.text; text: "Nazwa użytkownika"; color: Theme.text2; font: authUser.font }
                    }
                }
                Field {
                    visible: dlgBox.auth
                    TextInput {
                        id: authPass
                        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 14
                        clip: true
                        Keys.onReturnPressed: dlgLayer.close(true)
                        Text { anchors.verticalCenter: parent.verticalCenter; visible: !authPass.text; text: "Hasło"; color: Theme.text2; font: authPass.font }
                    }
                }
                Row {
                    anchors.right: parent.right
                    spacing: 8
                    PillButton {
                        visible: dlgBox.auth || dlgBox.type !== JavaScriptDialogRequest.DialogTypeAlert
                        text: dlgBox.type === JavaScriptDialogRequest.DialogTypeBeforeUnload ? "Zostań" : "Anuluj"
                        onClicked: dlgLayer.close(false)
                    }
                    PillButton {
                        primary: true
                        text: dlgBox.auth ? "Zaloguj się" : dlgBox.type === JavaScriptDialogRequest.DialogTypeBeforeUnload ? "Opuść stronę" : "OK"
                        onClicked: dlgLayer.close(true)
                    }
                }
            }
        }
    }

    component Field: Rectangle {
        width: parent ? parent.width : 0
        height: 40; radius: 11
        color: Theme.fill
        border.width: 1.5; border.color: Theme.accent
    }
}
