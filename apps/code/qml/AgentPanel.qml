pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Code

// Agent przy projekcie (Aster Intelligence przez usługę aster-assistant). Widzi to, co włączone w kontekście:
// otwarty plik, zaznaczenie, błędy z serwerów języków i kompilatora, stan gita — bez plików .env i wartości
// sekretów. Polecenia uruchamia w środowisku projektu (kontener), bezpieczne (tylko odczyt) od razu, resztę
// po kliknięciu. Zmiany w plikach przychodzą jako różnice do przejrzenia i akceptacji plik po pliku.
// Pasek u góry mówi, co agent właśnie robi.
Rectangle {
    id: ap
    property bool shown: false
    property string conversation: ""
    property var messages: []            // [{ role: user | assistant | action | error, text, … }]
    property var edits: []               // [{ path, rel, kind, oldText, newText, added, removed, state, error }]
    property string phase: ""            // "" | think | write | command | approval | review
    property string phaseText: ""
    // Kontekst do włączenia (z okna)
    property string fileRel: ""
    property int selectionLines: 0
    property int problemCount: 0
    property bool useFile: true
    property bool useSelection: true
    property bool useProblems: true
    property var buildContext: (opts) => ""      // ustawia Main
    property var fileText: (abs) => ""
    property string root: ""
    signal applyEdit(string path, string text)
    signal showEdit(string path, string title, var rows)
    signal openPath(string path)
    signal closed()

    readonly property bool busy: phase === "think" || phase === "write" || phase === "command" || phase === "approval"
    readonly property int pendingEdits: edits.filter(e => e.state === "pending").length
    readonly property string statusText: phase === "think" ? "Czytam kontekst i myślę…"
        : phase === "write" ? "Piszę odpowiedź…"
        : phase === "command" ? "Uruchamiam: " + phaseText
        : phase === "approval" ? "Czekam na Twoją zgodę"
        : pendingEdits ? "Zmiany do przejrzenia: " + pendingEdits + (pendingEdits === 1 ? " plik" : pendingEdits < 5 ? " pliki" : " plików")
        : ""

    visible: shown
    color: Theme.surface

    function open() { shown = true; Agent.refresh(); Qt.callLater(() => input.forceActiveFocus()); }
    function close() { shown = false; closed(); }
    function newConversation() {
        if (busy) Agent.cancel(conversation);
        conversation = "";
        messages = [];
        edits = [];
        phase = "";
    }
    function push(m) { messages = messages.concat([m]); Qt.callLater(() => list.positionViewAtEnd()); }
    function updateLast(role, fn) {
        const ms = messages.slice();
        for (let i = ms.length - 1; i >= 0; --i)
            if (ms[i].role === role) { ms[i] = Object.assign({}, ms[i]); fn(ms[i]); break; }
        messages = ms;
        Qt.callLater(() => list.positionViewAtEnd());
    }
    function send(text) {
        const t = text.trim();
        if (!t || busy) return;
        if (!Agent.available) { push({ role: "error", text: Agent.problem || "Aster Intelligence nie działa" }); return; }
        push({ role: "user", text: t });
        const ctx = buildContext({ file: useFile, selection: useSelection, problems: useProblems });
        phase = "think";
        const id = Agent.ask(conversation, t, ctx);
        if (id) conversation = id;
        else phase = "";
    }
    function ask(text) { open(); send(text); }

    // Odpowiedź gotowa — bloki zmian zamieniają się w pozycje do przejrzenia
    function takeEdits(text) {
        const parsed = Agent.parseEdits(text);
        const out = edits.filter(e => e.state === "pending" ? !parsed.some(p => ap.root + "/" + p.path === e.path) : true);
        const cards = [];
        for (const p of parsed) {
            const abs = p.path.startsWith("/") ? p.path : root + "/" + p.path.replace(/^\.\//, "");
            const old = fileText(abs);
            let res = p.kind === "file" ? { ok: true, text: p.content } : Agent.applyBlocks(old, p.blocks);
            const e = { path: abs, rel: p.path, kind: p.kind, blocks: p.blocks, oldText: old, newText: res.ok ? res.text : old,
                        state: res.ok ? "pending" : "failed", error: res.ok ? "" : res.error, added: 0, removed: 0, isNew: p.kind === "file" && !old };
            if (res.ok) {
                const rows = Agent.lineDiff(old, e.newText);
                e.added = rows.filter(r => r.kind === "+").length;
                e.removed = rows.filter(r => r.kind === "-").length;
            }
            out.push(e);
            cards.push(abs);
        }
        edits = out;
        return cards;
    }
    function editIndex(path) { for (let i = edits.length - 1; i >= 0; --i) if (edits[i].path === path) return i; return -1; }
    function setEditState(path, st) {
        const i = editIndex(path);
        if (i < 0) return;
        const es = edits.slice();
        es[i] = Object.assign({}, es[i], { state: st });
        edits = es;
        if (!pendingEdits && phase === "review") phase = "";
    }
    // Plik mógł się zmienić od propozycji — zmiana liczona na nowo na aktualnej treści, nigdy nie nadpisuje Twoich poprawek
    function refreshEdit(path) {
        const i = editIndex(path);
        if (i < 0) return null;
        const e = edits[i], cur = fileText(e.path);
        if (cur === e.oldText) return e;
        const res = e.kind === "edit" ? Agent.applyBlocks(cur, e.blocks) : { ok: false };
        const es = edits.slice();
        es[i] = Object.assign({}, e, res.ok ? { oldText: cur, newText: res.text } : { state: "failed", error: "Plik zmienił się od propozycji — poproś agenta o ponowienie" });
        edits = es;
        return es[i];
    }
    function accept(path) {
        const e = refreshEdit(path);
        if (!e || e.state !== "pending") return;
        applyEdit(e.path, e.newText);
        setEditState(path, "applied");
    }
    function reject(path) { setEditState(path, "rejected"); }
    function acceptAll() { for (const e of edits) if (e.state === "pending") accept(e.path); }
    function review(path) {
        const e = refreshEdit(path);
        if (e && e.state === "pending") showEdit(e.path, "Zmiana od agenta" + (e.isNew ? " (nowy plik)" : ""), Agent.lineDiff(e.oldText, e.newText));
    }

    Connections {
        target: Agent
        function onChunk(c, t) {
            if (c !== ap.conversation) return;
            if (ap.phase !== "write") { ap.phase = "write"; ap.push({ role: "assistant", text: "" }); }
            ap.updateLast("assistant", m => m.text += t);
        }
        function onFinished(c, text, badge) {
            if (c !== ap.conversation) return;
            const cards = ap.takeEdits(text);
            if (ap.phase !== "write") ap.push({ role: "assistant", text: "" });
            ap.updateLast("assistant", m => { m.text = Agent.stripEdits(text); m.badge = badge; m.edits = cards; });
            ap.phase = ap.pendingEdits ? "review" : "";
        }
        function onFailed(c, message) {
            if (c !== ap.conversation && c !== "") return;
            ap.push({ role: "error", text: message });
            ap.phase = "";
        }
        function onActionRequested(c, action, command, description, safe) {
            if (c !== ap.conversation) return;
            // Tekst przed poleceniem już przyszedł kawałkami — z niego zostaje opis, polecenie idzie do karty
            // Zdanie przed poleceniem jest opisem w karcie — nie powtarza się nad nią
            ap.updateLast("assistant", m => {
                m.text = Agent.stripEdits(m.text).replace(/```(?:bash|sh|shell)[\s\S]*$/, "").trim();
                if (m.text === description.trim()) m.text = "";
            });
            // Sięga po sekrety — nie uruchamia się nawet po kliknięciu
            if (Secrets.touchesSecrets(command)) {
                ap.push({ role: "action", action: action, command: command, text: "Polecenie sięga po sekrety (.env, klucze albo środowisko), więc nie zostało uruchomione.", state: "blocked", output: "", exit: 126 });
                Agent.refuse(c, action);
                return;
            }
            ap.push({ role: "action", action: action, command: command, text: description, state: safe ? "running" : "ask", output: "", exit: 0 });
            if (safe) ap.runAction(action, command);
            else ap.phase = "approval";
        }
        function onCommandOutput(c, action, t) {
            if (c !== ap.conversation) return;
            ap.updateLast("action", m => { if (m.action === action) m.output = String(m.output + t).slice(-6000); });
        }
        function onCommandDone(c, action, code, output) {
            if (c !== ap.conversation) return;
            ap.updateLast("action", m => { if (m.action === action) { m.state = "done"; m.exit = code; m.output = output.slice(-6000); } });
            ap.phase = "think";
        }
    }
    function runAction(action, command) {
        updateLast("action", m => { if (m.action === action) m.state = "running"; });
        phase = "command";
        phaseText = command.split("\n")[0].slice(0, 60);
        Agent.runCommand(conversation, action, command, root);
    }
    function declineAction(action) {
        updateLast("action", m => { if (m.action === action) m.state = "declined"; });
        phase = "think";
        Agent.decline(conversation, action);
    }

    Rectangle { width: 1; height: parent.height; color: Theme.line }

    // ——— Nagłówek ———
    Item {
        id: header
        x: 1; width: parent.width - 1; height: 44
        Icon { x: 14; anchors.verticalCenter: parent.verticalCenter; d: Icons.sparkles; size: 17; color: Theme.accentText }
        Column {
            x: 40; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 40 - hdrBtns.width - 12
            Text { text: "Agent"; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
            Text {
                width: parent.width; elide: Text.ElideRight
                text: !Agent.available ? "niedostępny" : Agent.badge || "Aster Intelligence"
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
            }
        }
        Row {
            id: hdrBtns
            anchors.right: parent.right; anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            HBtn { icon: "plus"; onClicked: ap.newConversation() }
            HBtn { icon: "close"; onClicked: ap.close() }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
    }

    // ——— Co agent robi ———
    Rectangle {
        id: statusBar
        x: 1; y: header.height
        width: parent.width - 1; height: ap.statusText ? 32 : 0
        visible: height > 0
        color: ap.phase === "approval" ? Qt.rgba(0.85, 0.6, 0.1, Theme.dark ? 0.18 : 0.12) : Theme.accentAlpha(Theme.dark ? 0.14 : 0.08)
        Rectangle {
            id: pulse
            x: 14; anchors.verticalCenter: parent.verticalCenter
            width: 8; height: 8; radius: 4
            color: ap.phase === "approval" ? "#D29922" : Theme.accent
            SequentialAnimation on opacity {
                running: ap.busy; loops: Animation.Infinite
                NumberAnimation { to: 0.25; duration: 600 }
                NumberAnimation { to: 1; duration: 600 }
            }
        }
        Text {
            x: 30; width: parent.width - 30 - stopBtn.width - 16
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: ap.statusText
            color: Theme.text; font.family: Theme.font; font.pixelSize: 12
        }
        HoverButton {
            id: stopBtn
            visible: ap.busy
            anchors.right: parent.right; anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: stopText.implicitWidth + 16; height: 22; radius: 6
            baseColor: Theme.fill
            onClicked: { Agent.cancel(ap.conversation); ap.phase = ""; }
            Text { id: stopText; anchors.centerIn: parent; text: "Zatrzymaj"; color: Theme.text; font.family: Theme.font; font.pixelSize: 11 }
        }
    }

    // ——— Rozmowa ———
    ListView {
        id: list
        x: 1; y: statusBar.y + statusBar.height
        width: parent.width - 1
        height: parent.height - y - reviewBox.height - inputBox.height
        clip: true
        spacing: 10
        topMargin: 12; bottomMargin: 12
        boundsBehavior: Flickable.StopAtBounds
        model: ap.messages
        delegate: Item {
            id: msg
            required property var modelData
            required property int index
            width: ListView.view.width
            height: body.height
            Loader {
                id: body
                x: 12; width: parent.width - 24
                sourceComponent: msg.modelData.role === "user" ? userMsg : msg.modelData.role === "action" ? actionMsg
                               : msg.modelData.role === "error" ? errorMsg : assistantMsg
                onLoaded: item.m = Qt.binding(() => msg.modelData)
            }
        }
        Column {
            visible: ap.messages.length === 0
            anchors.centerIn: parent
            width: parent.width - 48
            spacing: 10
            Icon { anchors.horizontalCenter: parent.horizontalCenter; d: Icons.sparkles; size: 30; stroke: 1.5; color: Theme.accentText; opacity: 0.8 }
            Text {
                width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                text: Agent.available ? "Zapytaj o kod, poproś o zmianę albo naprawę błędu. Agent widzi otwarty plik, zaznaczenie i problemy — zmiany pokaże do akceptacji."
                                      : (Agent.problem || "Aster Intelligence nie działa")
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.2
            }
            Repeater {
                model: Agent.available ? ["Wyjaśnij ten plik", "Napraw błędy z panelu Problemy", "Dopisz testy do zaznaczonego kodu"] : []
                delegate: HoverButton {
                    id: sug
                    required property string modelData
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: sugText.implicitWidth + 24; height: 30; radius: 8
                    baseColor: Theme.fill
                    onClicked: ap.send(modelData)
                    Text { id: sugText; anchors.centerIn: parent; text: sug.modelData; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                }
            }
        }
    }

    // ——— Zmiany do przejrzenia ———
    Rectangle {
        id: reviewBox
        x: 1; width: parent.width - 1
        anchors.bottom: inputBox.top
        height: ap.pendingEdits ? Math.min(220, reviewCol.implicitHeight + 16) : 0
        visible: height > 0
        color: Theme.fill
        Rectangle { width: parent.width; height: 1; color: Theme.line }
        Column {
            id: reviewCol
            x: 10; y: 8; width: parent.width - 20
            spacing: 4
            Item {
                width: parent.width; height: 26
                Text { anchors.verticalCenter: parent.verticalCenter; text: "ZMIANY · " + ap.pendingEdits; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.4 }
                Row {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    SmallPill { text: "Odrzuć wszystko"; onClicked: { for (const e of ap.edits) if (e.state === "pending") ap.reject(e.path); } }
                    SmallPill { text: "Zastosuj wszystko"; primary: true; onClicked: ap.acceptAll() }
                }
            }
            Repeater {
                model: ap.edits.filter(e => e.state === "pending")
                delegate: EditRow { required property var modelData; e: modelData; width: reviewCol.width }
            }
        }
    }

    // ——— Pole pytania ———
    Rectangle {
        id: inputBox
        x: 1; anchors.bottom: parent.bottom
        width: parent.width - 1; height: chips.height + inputFrame.height + 22
        color: Theme.surface
        Rectangle { width: parent.width; height: 1; color: Theme.line }
        Flow {
            id: chips
            x: 10; y: 8; width: parent.width - 20
            spacing: 4
            Chip { visible: !!ap.fileRel; icon: "doc"; text: ap.fileRel.split("/").pop(); on: ap.useFile; onClicked: ap.useFile = !ap.useFile }
            Chip { visible: ap.selectionLines > 0; icon: "cursor"; text: "zaznaczenie · " + ap.selectionLines; on: ap.useSelection; onClicked: ap.useSelection = !ap.useSelection }
            Chip { visible: ap.problemCount > 0; icon: "alertCircle"; text: "problemy · " + ap.problemCount; on: ap.useProblems; onClicked: ap.useProblems = !ap.useProblems }
        }
        Rectangle {
            id: inputFrame
            x: 10; y: chips.y + chips.height + 6
            width: parent.width - 20; height: Math.min(140, Math.max(40, input.contentHeight + 18))
            radius: 12
            color: Theme.fill
            border.width: input.activeFocus ? 1.5 : 0; border.color: Theme.accent
            Flickable {
                id: inFlick
                x: 12; y: 9
                width: parent.width - 24 - sendBtn.width; height: parent.height - 18
                contentHeight: input.contentHeight
                clip: true
                TextEdit {
                    id: input
                    width: inFlick.width
                    wrapMode: TextEdit.Wrap
                    color: Theme.text; selectionColor: Theme.accentSoft; selectedTextColor: Theme.text
                    font.family: Theme.font; font.pixelSize: 13
                    Keys.onPressed: (e) => {
                        if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & Qt.ShiftModifier)) {
                            ap.send(input.text);
                            if (!ap.busy || ap.phase === "think") input.text = "";
                            e.accepted = true;
                        } else if (e.key === Qt.Key_Escape) { ap.close(); e.accepted = true; }
                    }
                    Text { visible: !input.text; text: ap.busy ? "Agent pracuje…" : "Napisz, co zrobić"; color: Theme.text2; font: input.font; width: parent.width; wrapMode: Text.Wrap }
                }
            }
            HoverButton {
                id: sendBtn
                anchors.right: parent.right; anchors.rightMargin: 6
                anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                width: 28; height: 28; radius: 14
                baseColor: ap.busy ? Theme.surface : Theme.accent
                enabled: ap.busy || !!input.text.trim()
                opacity: enabled ? 1 : 0.4
                onClicked: { if (ap.busy) { Agent.cancel(ap.conversation); ap.phase = ""; } else { ap.send(input.text); input.text = ""; } }
                Icon { anchors.centerIn: parent; d: ap.busy ? Icons.stop : Icons.up; size: 13; stroke: 2.2; color: ap.busy ? Theme.text : "white" }
            }
        }
    }

    // ——— Wiadomości ———
    Component {
        id: userMsg
        Item {
            id: um
            property var m: ({})
            width: parent ? parent.width : 0; height: ub.height
            Rectangle {
                id: ub
                anchors.right: parent.right
                width: Math.min(parent.width * 0.88, ut.implicitWidth + 24); height: ut.implicitHeight + 16
                radius: 12
                color: Theme.accentSoft
                Text { id: ut; x: 12; y: 8; width: Math.min(implicitWidth, um.width * 0.88 - 24); wrapMode: Text.Wrap; text: um.m.text || ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
            }
        }
    }
    Component {
        id: assistantMsg
        Column {
            id: am
            property var m: ({})
            width: parent ? parent.width : 0
            spacing: 6
            Text {
                width: parent.width
                visible: !!(am.m.text || "").replace(/\[\[zmiana:[^\]]*\]\]/g, "").trim()
                wrapMode: Text.Wrap
                textFormat: Text.MarkdownText
                text: (am.m.text || "").replace(/\[\[zmiana:[^\]]*\]\]/g, "").trim()
                color: Theme.text; font.family: Theme.font; font.pixelSize: 13
                lineHeight: 1.15
                onLinkActivated: (l) => Qt.openUrlExternally(l)
            }
            Repeater {
                model: am.m.edits || []
                delegate: EditRow {
                    required property string modelData
                    width: am.width
                    e: { ap.edits; const i = ap.editIndex(modelData); return i >= 0 ? ap.edits[i] : ({}); }
                }
            }
            Text { visible: !!am.m.badge; text: am.m.badge || ""; color: Theme.text2; font.family: Theme.font; font.pixelSize: 10 }
        }
    }
    Component {
        id: actionMsg
        Rectangle {
            id: acm
            property var m: ({})
            property bool expanded: false
            width: parent ? parent.width : 0; height: acCol.implicitHeight + 20
            radius: 12
            color: Theme.fill
            border.width: acm.m.state === "ask" ? 1.5 : 0; border.color: "#D29922"
            Column {
                id: acCol
                x: 12; y: 10; width: parent.width - 24
                spacing: 6
                Row {
                    spacing: 6
                    Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.terminal; size: 13; color: Theme.text2 }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: acm.m.state === "ask" ? "Agent chce uruchomić" : acm.m.state === "running" ? "Uruchamiam…"
                            : acm.m.state === "blocked" ? "Zablokowane"
                            : acm.m.state === "declined" ? "Pominięte" : acm.m.exit === 0 ? "Gotowe" : "Zakończone z kodem " + acm.m.exit
                        color: acm.m.state === "done" && acm.m.exit !== 0 ? Theme.danger : Theme.text2
                        font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
                    }
                }
                Text { visible: !!acm.m.text; width: parent.width; wrapMode: Text.Wrap; text: acm.m.text || ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
                Rectangle {
                    width: parent.width; height: cmdText.implicitHeight + 12; radius: 7
                    color: Theme.windowGlass
                    Text { id: cmdText; x: 8; y: 6; width: parent.width - 16; wrapMode: Text.WrapAnywhere; text: acm.m.command || ""; color: Theme.text; font.family: "JetBrains Mono"; font.pixelSize: 12 }
                }
                Row {
                    visible: acm.m.state === "ask"
                    spacing: 6
                    SmallPill { text: "Uruchom"; primary: true; onClicked: ap.runAction(acm.m.action, acm.m.command) }
                    SmallPill { text: "Pomiń"; onClicked: ap.declineAction(acm.m.action) }
                }
                Text {
                    visible: !!acm.m.output && acm.m.state !== "ask"
                    text: acm.expanded ? "Ukryj wynik" : "Pokaż wynik"
                    color: Theme.accentText; font.family: Theme.font; font.pixelSize: 11
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: acm.expanded = !acm.expanded }
                }
                Text {
                    visible: acm.expanded || acm.m.state === "running"
                    width: parent.width; wrapMode: Text.WrapAnywhere; maximumLineCount: acm.expanded ? 400 : 6
                    elide: Text.ElideLeft
                    text: (acm.m.output || "").trim().split("\n").slice(acm.expanded ? -200 : -6).join("\n")
                    color: Theme.text2; font.family: "JetBrains Mono"; font.pixelSize: 11
                }
            }
        }
    }
    Component {
        id: errorMsg
        Rectangle {
            id: em
            property var m: ({})
            width: parent ? parent.width : 0; height: et.implicitHeight + 16; radius: 10
            color: Qt.rgba(0.9, 0.28, 0.3, Theme.dark ? 0.16 : 0.08)
            Text { id: et; x: 10; y: 8; width: parent.width - 20; wrapMode: Text.Wrap; text: em.m.text || ""; color: Theme.danger; font.family: Theme.font; font.pixelSize: 12 }
        }
    }

    component EditRow: Rectangle {
        id: er
        property var e: ({})
        height: 40; radius: 9
        color: erArea.containsMouse ? Theme.hover : Theme.surface
        border.width: 1; border.color: Theme.line
        MouseArea { id: erArea; anchors.fill: parent; hoverEnabled: true; onClicked: if (er.e.state === "pending") ap.review(er.e.path); else if (er.e.path) ap.openPath(er.e.path) }
        FileIcon { x: 10; anchors.verticalCenter: parent.verticalCenter; name: (er.e.rel || "").split("/").pop(); size: 15 }
        Column {
            x: 32; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 32 - erBtns.width - 10
            Text { width: parent.width; elide: Text.ElideMiddle; text: er.e.rel || ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
            Text {
                width: parent.width; elide: Text.ElideRight
                textFormat: Text.StyledText
                text: er.e.state === "failed" ? "<font color=\"" + Theme.danger + "\">" + er.e.error + "</font>"
                    : er.e.state === "applied" ? "Zastosowano" : er.e.state === "rejected" ? "Odrzucono"
                    : (er.e.isNew ? "nowy plik · " : "") + "<font color=\"" + (Theme.dark ? "#3FB950" : "#1A7F37") + "\">+" + er.e.added + "</font> <font color=\"" + Theme.danger + "\">−" + er.e.removed + "</font>"
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
            }
        }
        Row {
            id: erBtns
            visible: er.e.state === "pending"
            anchors.right: parent.right; anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            HBtn { icon: "close"; onClicked: ap.reject(er.e.path) }
            HBtn { icon: "check"; tint: Theme.dark ? "#3FB950" : "#1A7F37"; onClicked: ap.accept(er.e.path) }
        }
    }
    component HBtn: HoverButton {
        id: hb
        property string icon
        property color tint: Theme.text2
        width: 28; height: 28; radius: 7
        Icon { anchors.centerIn: parent; d: Icons[hb.icon] || ""; size: 13; stroke: 2; color: hb.tint }
    }
    component SmallPill: HoverButton {
        id: sp
        property string text
        property bool primary: false
        width: spText.implicitWidth + 18; height: 24; radius: 7
        baseColor: primary ? Theme.accent : Theme.surface
        Text { id: spText; anchors.centerIn: parent; text: sp.text; color: sp.primary ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium }
    }
    component Chip: HoverButton {
        id: ch
        property string icon
        property string text
        property bool on: true
        width: chRow.implicitWidth + 14; height: 22; radius: 11
        baseColor: on ? Theme.accentSoft : Theme.fill
        opacity: on ? 1 : 0.6
        Row {
            id: chRow
            anchors.centerIn: parent
            spacing: 4
            Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons[ch.icon] || ""; size: 11; color: ch.on ? Theme.accentText : Theme.text2 }
            Text { anchors.verticalCenter: parent.verticalCenter; text: ch.text; color: ch.on ? Theme.text : Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.strikeout: !ch.on }
        }
    }
}
