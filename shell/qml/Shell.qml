import QtQuick
import QtQml.Models
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
            onAskOpened: edgeGlow.flash()
            onAssistantPanelRequested: show => {
                if (!show) { assistWin.close(); return; }
                startWin.close(); controlWin.close(); assistWin.show();
            }
        }
    }
    property var clock: ClockWindow {}
    property var start: StartWindow { id: startWin }
    property var control: ControlCenterWindow { id: controlWin }
    property var assistant: AssistantWindow { id: assistWin }   // panel Aster Intelligence z prawej
    // Poświata na krawędziach ekranu, gdy Aster Intelligence myśli
    property var glow: EdgeGlowWindow {
        id: edgeGlow
        active: (Assistant.busy && !Assistant.waiting) || Platform.env("ASTER_SHOT_GLOW") !== ""
    }
    property var auth: AuthWindow {}            // hasło administratora (agent polkit)
    property var dock: DockWindow {
        startOpen: startWin.open
        onStartRequested: { controlWin.close(); startWin.toggle(); }
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
    // Do testów: ASTER_SHOT_ASK="pytanie|kolejne|…" — pierwsze w wyspie, kolejne jak dopytanie
    // (ASTER_SHOT_GLOW=1 zapala poświatę ekranu bez pytania)
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
            Qt.callLater(() => { if (assistWin.open) assistWin.askNow(q); else if (h) h.askNow(q); });
        }
    }

    // Klawisz Super (KWin wywołuje org.kde.plasmashell → activateLauncherMenu)
    property var superKey: Connections {
        target: Platform
        function onLauncherRequested() { controlWin.close(); startWin.toggle(); }
    }
}
