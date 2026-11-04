import QtQuick
import QtQml.Models
import org.kde.taskmanager as TaskManager
import Aster.Shell

// Korzeń powłoki: tworzy jej okna-warstwy. Tapeta i górny pasek są na każdym ekranie (jak w macOS),
// dok, Start i centrum sterowania — na głównym. Podłączenie albo odłączenie monitora tworzy je od nowa.
QtObject {
    id: shell
    property var wallpapers: Instantiator {
        model: Qt.application.screens
        delegate: WallpaperWindow {
            required property var modelData
            screen: modelData
        }
    }
    property var horizons: Instantiator {
        model: Qt.application.screens
        delegate: HorizonWindow {
            required property var modelData
            screen: modelData
            primary: modelData === Qt.application.screens[0]
            controlOpen: controlWin.open
            assistantOpen: assistWin.open
            onStartRequested: { controlWin.close(); assistWin.close(); startWin.toggle(); }
            onControlRequested: { startWin.close(); assistWin.close(); controlWin.toggle(); }
            onChatsRequested: {
                if (assistWin.open) { assistWin.close(); return; }
                startWin.close(); controlWin.close(); assistWin.show();
                if (Assistant.count === 0) assistWin.openHistory();
            }
            onAssistantPanelRequested: show => {
                if (!show) { assistWin.close(); return; }
                startWin.close(); controlWin.close(); assistWin.show();
            }
        }
    }
    // Okna dla Aster Intelligence (D-Bus org.aster.Shell): każde okno osobno, ze wszystkich ekranów i pulpitów
    property var windowList: TaskManager.TasksModel {
        groupMode: TaskManager.TasksModel.GroupDisabled
        filterByVirtualDesktop: false
        filterByActivity: false
        filterByScreen: false
        filterHidden: false
        Component.onCompleted: Windows.model = this
    }
    property var clock: ClockWindow {}
    property var start: StartWindow { id: startWin }
    property var control: ControlCenterWindow { id: controlWin }
    property var assistant: AssistantWindow { id: assistWin }   // panel Aster Intelligence z prawej
    property var auth: AuthWindow {}            // hasło administratora (agent polkit)
    property var dock: DockWindow {
        startOpen: startWin.open
        onStartRequested: { controlWin.close(); startWin.toggle(); }
    }

    // Agent znalazł wcześniejszą rozmowę — otwiera ją w panelu
    property var shownConversation: Connections {
        target: Assistant
        function onConversationShown() {
            const h = shell.horizons.objectAt(0);
            if (h) h.closeAsk();
            startWin.close(); controlWin.close();
            if (!assistWin.open) assistWin.show();
        }
    }

    // Super+Spacja: pole pytania w wyspie głównego ekranu (albo zamknięcie otwartego panelu)
    property var assistantKey: Connections {
        target: Assistant
        function onToggleRequested() {
            const h = shell.horizons.objectAt(0);
            if (assistWin.open) assistWin.close();
            else if (h) h.toggleAsk();
        }
    }
    // Do testów: ASTER_SHOT_ASK="pytanie|kolejne|…|^" — pierwsze w wyspie, kolejne jak dopytanie, „^” chowa rozmowę do kropli
    property var shotAsk: Timer {
        readonly property var questions: Platform.env("ASTER_SHOT_ASK") === "" ? [] : Platform.env("ASTER_SHOT_ASK").split("|")
        property int next: 0
        running: questions.length > 0
        interval: 1300
        onTriggered: {
            const h = shell.horizons.objectAt(0);
            // „-”: tylko otwórz pole pytania (np. z ASTER_SHOT_SELECTION — narzędzia do pisania)
            if (h) { if (questions[0] === "-") h.openAsk(); else h.askNow(questions[0]); }
            next = 1;
        }
    }
    property var shotAskNext: Connections {
        target: Assistant
        enabled: shell.shotAsk.questions.length > 1
        function onAnswered() {
            if (shell.shotAsk.next >= shell.shotAsk.questions.length) return;
            const q = shell.shotAsk.questions[shell.shotAsk.next++];
            const h = shell.horizons.objectAt(0);
            // „^”: schowaj rozmowę (do kropli pod prawą wyspą)
            if (q === "^") { Qt.callLater(() => { if (h) h.closeAsk(); assistWin.close(); }); return; }
            Qt.callLater(() => { if (assistWin.open) assistWin.askNow(q); else if (h) h.askNow(q); });
        }
    }

    // Klawisz Super (KWin wywołuje org.kde.plasmashell → activateLauncherMenu)
    property var superKey: Connections {
        target: Platform
        function onLauncherRequested() { controlWin.close(); startWin.toggle(); }
    }
}
