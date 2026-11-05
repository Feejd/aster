pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Code

// Wdrożenie jednym kliknięciem i GitHub. Cele: własny serwer przez SSH (budowanie, rsync, polecenie
// po wdrożeniu), GitHub Pages, Netlify, Vercel, Cloudflare Pages. Ustawienia w .aster/wdrozenie.json
// (bez sekretów — klucze hostingów są w Sekretach projektu), wdrożenie biegnie jako zadanie z logami.
Rectangle {
    id: dv
    property bool shown: false
    property string root
    property var cfg: ({})
    property string tokenText: ""
    signal deploy(var cfg)
    signal openSecrets()
    signal closed()

    visible: shown
    color: Theme.dark ? "#090A0D" : "#FFFFFF"
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

    readonly property var targets: [
        { id: "ssh", name: "Własny serwer", desc: "SSH i rsync", icon: "terminal", needs: [] },
        { id: "pages", name: "GitHub Pages", desc: "Strona statyczna z repozytorium", icon: "gitBranch", needs: [] },
        { id: "netlify", name: "Netlify", desc: "Strona statyczna", icon: "globe", needs: ["NETLIFY_AUTH_TOKEN"] },
        { id: "vercel", name: "Vercel", desc: "Frontend i funkcje", icon: "globe", needs: ["VERCEL_TOKEN"] },
        { id: "cloudflare", name: "Cloudflare Pages", desc: "Strona statyczna", icon: "globe", needs: ["CLOUDFLARE_API_TOKEN", "CLOUDFLARE_ACCOUNT_ID"] }
    ]
    readonly property var target: targets.find(t => t.id === cfg.target) || targets[0]
    readonly property var missing: target.needs.filter(n => Secrets.names.indexOf(n) < 0)

    // Domyślne: frontend z package.json (build → dist), cel — ostatnio użyty albo własny serwer
    function defaults() {
        const fe = Project.exists(root + "/frontend/package.json") ? "frontend" : Project.exists(root + "/package.json") ? "." : "";
        const out = fe === "." ? "dist" : fe ? fe + "/dist" : ".";
        return { target: "ssh", host: "", path: "~/aplikacje/" + Project.name.toLowerCase().replace(/[^a-z0-9]+/g, "-"),
                 buildDir: fe || ".", build: fe ? "npm run build" : "", send: fe ? out : ".", post: "", project: Project.name.toLowerCase().replace(/[^a-z0-9]+/g, "-") };
    }
    function load() {
        let c = {};
        try { c = JSON.parse(Agent.readFile(root + "/.aster/wdrozenie.json") || "{}"); } catch (e) {}
        cfg = Object.assign(defaults(), c);
    }
    function save() { Project.save(root + "/.aster/wdrozenie.json", JSON.stringify(cfg, null, 2) + "\n", "UTF-8", "LF"); }
    function set(k, v) { const c = Object.assign({}, cfg); c[k] = v; cfg = c; }
    function open() { load(); shown = true; GitHub.refresh(); }
    function close() { shown = false; closed(); }
    readonly property bool configured: !!cfg.target && (cfg.target !== "ssh" || !!cfg.host)

    Item {
        id: header
        width: parent.width; height: 58
        Row {
            x: col.x; anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.upload; size: 18; color: Theme.accentText }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "Wdrożenie i GitHub"; color: Theme.text; font.family: Theme.font; font.pixelSize: 18; font.weight: Font.DemiBold }
        }
        HoverButton {
            anchors.right: parent.right; anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            width: 30; height: 30; radius: 8
            onClicked: dv.close()
            Icon { anchors.centerIn: parent; d: Icons.close; size: 13; stroke: 2; color: Theme.text2 }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
    }

    Flickable {
        y: header.height
        width: parent.width; height: parent.height - y
        contentHeight: col.height + 40
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: col
            x: Math.max(24, (parent.width - width) / 2); y: 18
            width: Math.min(760, dv.width - 48)
            spacing: 14

            // ——— GitHub ———
            Text { text: "GITHUB"; color: Theme.accentText; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.6 }
            Rectangle {
                width: parent.width; height: ghCol.implicitHeight + 28; radius: 12
                color: Theme.fill
                Column {
                    id: ghCol
                    x: 16; y: 14; width: parent.width - 32
                    spacing: 10
                    Text {
                        width: parent.width; wrapMode: Text.Wrap
                        text: GitHub.login ? "Zalogowano jako " + GitHub.login + (GitHub.method === "gh" ? " (gh)" : " (token w portfelu)") + " — wysyłanie i pobieranie działa bez hasła."
                                           : "Zaloguj się, żeby wysyłać zmiany i tworzyć repozytoria bez terminala."
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 13
                    }
                    // Kod jednorazowy przy logowaniu przez przeglądarkę
                    Rectangle {
                        visible: !!GitHub.code
                        width: parent.width; height: 70; radius: 10
                        color: Theme.surface
                        Column {
                            anchors.centerIn: parent
                            spacing: 4
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: GitHub.code; color: Theme.text; font.family: "JetBrains Mono"; font.pixelSize: 24; font.weight: Font.Bold; font.letterSpacing: 2 }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Wpisz ten kod na stronie github.com/login/device (otworzyła się w przeglądarce)"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11 }
                        }
                    }
                    Flow {
                        width: parent.width
                        spacing: 8
                        Btn { visible: !GitHub.login && !GitHub.code; text: GitHub.hasGh() ? "Zaloguj przez przeglądarkę" : "Zaloguj przez przeglądarkę (zainstaluje gh)"; primary: true
                              onClicked: GitHub.hasGh() ? GitHub.loginBrowser() : dv.installGh() }
                        Btn { visible: !!GitHub.code; text: "Anuluj"; onClicked: GitHub.cancelLogin() }
                        Btn { visible: !!GitHub.login; text: "Wyloguj"; onClicked: GitHub.logout() }
                        Btn {
                            visible: !!GitHub.login && Project.isGit && !Project.upstream
                            text: "Utwórz repozytorium na GitHubie i wyślij"; primary: true
                            onClicked: GitHub.createRepo(dv.root, Project.name.toLowerCase().replace(/[^a-z0-9._-]+/g, "-"), true)
                        }
                    }
                    Row {
                        visible: !GitHub.login && !GitHub.code
                        width: parent.width
                        spacing: 6
                        Rectangle {
                            width: parent.width - tokBtn.width - 6; height: 34; radius: 9
                            color: Theme.surface
                            TextInput {
                                id: tok
                                x: 10; width: parent.width - 20
                                anchors.verticalCenter: parent.verticalCenter
                                echoMode: TextInput.Password
                                color: Theme.text; font.family: "JetBrains Mono"; font.pixelSize: 12
                                clip: true
                                onAccepted: GitHub.loginToken(text)
                                Text { anchors.verticalCenter: parent.verticalCenter; visible: !tok.text; text: "albo token (github.com → Settings → Developer settings → Tokens), uprawnienie repo"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; width: parent.width; elide: Text.ElideRight }
                            }
                        }
                        Btn { id: tokBtn; text: "Zapisz token"; enabled: !!tok.text; onClicked: { GitHub.loginToken(tok.text); tok.text = ""; } }
                    }
                }
            }

            // ——— Cel wdrożenia ———
            Text { topPadding: 6; text: "WDROŻENIE"; color: Theme.accentText; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.6 }
            Flow {
                width: parent.width
                spacing: 8
                Repeater {
                    model: dv.targets
                    delegate: HoverButton {
                        id: card
                        required property var modelData
                        readonly property bool on: dv.cfg.target === modelData.id
                        width: (col.width - 4 * 8) / 5; height: 70; radius: 12
                        baseColor: on ? Theme.accentSoft : Theme.fill
                        onClicked: dv.set("target", modelData.id)
                        Rectangle { anchors.fill: parent; radius: 12; color: "transparent"; border.width: card.on ? 1.5 : 0; border.color: Theme.accent }
                        Column {
                            x: 12; y: 12; width: parent.width - 24
                            spacing: 4
                            Icon { d: Icons[card.modelData.icon] || ""; size: 15; color: card.on ? Theme.accentText : Theme.text2 }
                            Text { width: parent.width; elide: Text.ElideRight; text: card.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                            Text { width: parent.width; elide: Text.ElideRight; text: card.modelData.desc; color: Theme.text2; font.family: Theme.font; font.pixelSize: 10 }
                        }
                    }
                }
            }

            Field { visible: dv.cfg.target === "ssh"; label: "Serwer (użytkownik@adres)"; key: "host"; placeholder: "ola@moj-serwer.pl"; mono: true }
            Field { visible: dv.cfg.target === "ssh"; label: "Folder na serwerze"; key: "path"; placeholder: "~/aplikacje/nazwa"; mono: true }
            Row {
                width: parent.width; spacing: 10
                Field { width: (parent.width - 10) * 0.4; label: "Budowanie — folder"; key: "buildDir"; placeholder: "frontend"; mono: true }
                Field { width: (parent.width - 10) * 0.6; label: "Polecenie budowania (puste — bez budowania)"; key: "build"; placeholder: "npm run build"; mono: true }
            }
            Field { visible: dv.cfg.target !== "vercel"; label: dv.cfg.target === "ssh" ? "Co wysłać (folder; „.” — cały projekt bez node_modules, .venv, .git i .env)" : "Folder ze zbudowaną stroną"; key: "send"; placeholder: "frontend/dist"; mono: true }
            Field { visible: dv.cfg.target === "ssh"; label: "Polecenie na serwerze po wysłaniu (opcjonalne)"; key: "post"; placeholder: "docker compose up -d --build   albo   systemctl --user restart aplikacja"; mono: true }
            Field { visible: dv.cfg.target === "cloudflare" || dv.cfg.target === "netlify"; label: dv.cfg.target === "netlify" ? "Identyfikator strony (NETLIFY_SITE_ID, opcjonalny)" : "Nazwa projektu w Cloudflare Pages"; key: "project"; placeholder: "moja-strona"; mono: true }

            Text {
                visible: dv.cfg.target === "ssh"
                width: parent.width; wrapMode: Text.Wrap
                text: "Logowanie kluczem SSH (ssh-agent albo ~/.ssh) — Aster Code nie pyta o hasło serwera."
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
            }
            Text {
                visible: dv.cfg.target === "pages"
                width: parent.width; wrapMode: Text.Wrap
                text: GitHub.login ? "Zbudowana strona trafi na gałąź gh-pages repozytorium origin." : "Najpierw zaloguj się do GitHuba (wyżej)."
                color: GitHub.login ? Theme.text2 : Theme.danger; font.family: Theme.font; font.pixelSize: 12
            }
            Rectangle {
                visible: dv.missing.length > 0
                width: parent.width; height: 52; radius: 10
                color: Qt.rgba(0.85, 0.6, 0.1, Theme.dark ? 0.16 : 0.10)
                Text {
                    x: 14; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 28 - secBtn.width
                    wrapMode: Text.Wrap
                    text: "Brakuje kluczy w Sekretach projektu: " + dv.missing.join(", ")
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 12
                }
                Btn { id: secBtn; anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: "Dodaj w Sekretach"; onClicked: dv.openSecrets() }
            }

            Item {
                width: parent.width; height: 40
                Row {
                    anchors.right: parent.right
                    spacing: 8
                    Btn { text: "Zapisz"; onClicked: { dv.save(); Project.message("Zapisano ustawienia wdrożenia (.aster/wdrozenie.json)"); } }
                    Btn {
                        text: "Wdróż"; primary: true
                        enabled: dv.configured && dv.missing.length === 0 && (dv.cfg.target !== "pages" || !!GitHub.login)
                        onClicked: { dv.save(); dv.shown = false; dv.deploy(dv.cfg); }
                    }
                }
            }
        }
    }

    function installGh() {
        if (ProjectEnv.state === "ready") { Project.message("Instaluję gh w kontenerze — potem zaloguj się ponownie"); dv.installRequested("gh"); }
        else Project.message("Program gh nie jest zainstalowany — utwórz kontener projektu albo zaloguj się tokenem");
    }
    signal installRequested(string pkg)

    component Btn: HoverButton {
        id: b
        property string text
        property bool primary: false
        width: bt.implicitWidth + 28; height: 34; radius: 9
        baseColor: primary ? Theme.accent : Theme.surface
        opacity: enabled ? 1 : 0.45
        Text { id: bt; anchors.centerIn: parent; text: b.text; color: b.primary ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
    }
    component Field: Column {
        id: fld
        property string label
        property string key
        property string placeholder
        property bool mono: false
        width: col.width
        spacing: 6
        Text { text: fld.label; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
        Rectangle {
            width: fld.width; height: 36; radius: 9
            color: Theme.fill
            border.width: input.activeFocus ? 1.5 : 0; border.color: Theme.accent
            TextInput {
                id: input
                x: 12; width: parent.width - 24
                anchors.verticalCenter: parent.verticalCenter
                text: dv.cfg[fld.key] || ""
                onTextEdited: dv.set(fld.key, text)
                color: Theme.text; selectionColor: Theme.accentSoft; selectedTextColor: Theme.text
                font.family: fld.mono ? "JetBrains Mono" : Theme.font; font.pixelSize: 13
                clip: true
                Text { anchors.verticalCenter: parent.verticalCenter; visible: !input.text; text: fld.placeholder; color: Theme.text2; font: input.font; width: parent.width; elide: Text.ElideRight }
            }
        }
    }
}
