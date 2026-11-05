pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Launch
import "LaunchIcons.js" as LI

// Cel wdrożenia: co to za projekt, dokąd (własny serwer albo hosting), klucz SSH, domena
Flickable {
    id: page
    required property var project
    required property var app
    readonly property bool ssh: project.target === "ssh"
    property var keys: Launch.sshKeys()
    property string probeText: ""
    property bool probeOk: false
    property bool probing: false
    property var dns: null
    property var hosting: ssh ? null : Launch.hostingInfo(project.target)
    property string loginText: ""
    property bool loggedIn: false
    property string hostingNote: ""

    contentHeight: col.height + 48
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    Component.onCompleted: {
        if (!ssh) Launch.checkHostingLogin(project.target);
    }
    onProjectChanged: if (!ssh && (!hosting || hosting.kind !== project.target)) { hosting = Launch.hostingInfo(project.target); loginText = ""; Launch.checkHostingLogin(project.target); }
    readonly property string pid: project.id
    onPidChanged: { probeText = ""; probing = false; dns = null; hostingNote = ""; }

    function set(key, value) { Launch.updateProject(project.id, { [key]: value }); }

    Connections {
        target: Launch
        function onProbed(id, ok, message) { if (id === page.project.id) { page.probing = false; page.probeOk = ok; page.probeText = message; } }
        function onDnsChecked(id, result) { if (id === page.project.id) page.dns = result; }
        function onHostingChecked(kind, ok, who) {
            if (kind !== page.project.target) return;
            page.hosting = Launch.hostingInfo(kind);
            page.loggedIn = ok;
            page.loginText = !page.hosting.installed ? "" : ok ? "Zalogowano" + (who ? ": " + who : "") : "Nie zalogowano";
        }
        function onHostingMessage(kind, message) { if (kind === page.project.target) page.hostingNote = message; }
    }

    Column {
        id: col
        x: 28; y: 24
        width: page.width - 56
        spacing: 16

        // ——— Projekt ———
        Card {
            title: "Projekt"
            subtitle: "Rozpoznany automatycznie — popraw, jeśli trzeba."
            Field { label: "Nazwa"; value: page.project.name; onCommitted: (t) => page.set("name", t.trim() || page.project.name) }
            Item {
                width: parent.width; height: 34
                Text { y: 8; text: "Typ"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
                Row {
                    x: 170
                    spacing: 6
                    Repeater {
                        model: [["static", "Statyczna strona"], ["node", "Node.js"], ["python", "Python"], ["docker", "Docker"], ["compose", "Compose"]]
                        delegate: HoverButton {
                            id: typeBtn
                            required property var modelData
                            readonly property bool active: page.project.type === modelData[0]
                            width: typeLabel.implicitWidth + 24; height: 32; radius: 16
                            baseColor: active ? Theme.accent : Theme.fill
                            color: active ? Theme.accent : (hovered ? Theme.hover : Theme.fill)
                            onClicked: page.set("type", modelData[0])
                            Text { id: typeLabel; anchors.centerIn: parent; text: typeBtn.modelData[1]; color: typeBtn.active ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                        }
                    }
                }
            }
            Field {
                label: "Budowanie"
                value: page.project.build
                placeholder: "bez budowania"
                mono: true
                hint: "Na tym komputerze, przed wysłaniem (np. npm install && npm run build)."
                onCommitted: (t) => page.set("build", t.trim())
            }
            Field {
                visible: page.project.type === "static"
                label: "Folder strony"
                value: page.project.output
                placeholder: "cały folder projektu"
                mono: true
                hint: "Co trafi na serwer — np. dist albo build po zbudowaniu."
                onCommitted: (t) => page.set("output", t.trim().replace(/^\/+|\/+$/g, ""))
            }
            Field {
                visible: page.project.type === "node" || page.project.type === "python"
                label: "Uruchomienie"
                value: page.project.start
                mono: true
                hint: "W folderze wersji na serwerze. Port podaje zmienna $PORT."
                onCommitted: (t) => page.set("start", t.trim())
            }
            Field {
                visible: page.project.type !== "static"
                label: "Port aplikacji"
                value: String(page.project.port)
                numeric: true
                hint: page.project.type === "docker" || page.project.type === "compose" ? "Port, na którym słucha kontener; Caddy przekaże do niego ruch." : "Aplikacja słucha tylko lokalnie (127.0.0.1) — z internetu ruch idzie przez Caddy."
                onCommitted: (t) => page.set("port", Number(t))
            }
        }

        // ——— Dokąd ———
        Card {
            title: "Dokąd wdrażać"
            Grid {
                width: parent.width
                columns: 4
                columnSpacing: 10
                Repeater {
                    model: [
                        { id: "ssh", name: "Własny serwer", text: "VPS albo komputer z SSH", icon: LI.server },
                        { id: "netlify", name: "Netlify", text: "Strony statyczne", icon: LI.cloud },
                        { id: "vercel", name: "Vercel", text: "Strony i Node.js", icon: LI.cloud },
                        { id: "cloudflare", name: "Cloudflare Pages", text: "Strony statyczne", icon: LI.cloud }
                    ]
                    delegate: HoverButton {
                        id: tgt
                        required property var modelData
                        readonly property bool active: page.project.target === modelData.id
                        width: (parent.width - 30) / 4; height: 76; radius: 12
                        baseColor: active ? Theme.accentSoft : Theme.fill
                        color: active ? Theme.accentSoft : (hovered ? Theme.hover : Theme.fill)
                        border.width: active ? 1.5 : 0; border.color: Theme.accent
                        onClicked: page.set("target", modelData.id)
                        Column {
                            x: 12; y: 12; width: parent.width - 24
                            spacing: 4
                            Icon { d: tgt.modelData.icon; size: 18; stroke: 1.8; color: tgt.active ? Theme.accentText : Theme.text2 }
                            Text { width: parent.width; elide: Text.ElideRight; text: tgt.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                            Text { width: parent.width; elide: Text.ElideRight; text: tgt.modelData.text; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11 }
                        }
                    }
                }
            }
        }

        // ——— Własny serwer ———
        Card {
            visible: page.ssh
            title: "Serwer"
            subtitle: "Połączenie przez SSH kluczem. Pliki trafią do /srv/aster-launch/" + (page.project.slug || "") + ", a Caddy poda stronę z HTTPS."
            Field { label: "Adres serwera"; value: page.project.host; placeholder: "np. 203.0.113.10 albo vps.mojadomena.pl"; mono: true; onCommitted: (t) => page.set("host", t.trim()) }
            Field { label: "Użytkownik"; value: page.project.user; placeholder: "root"; mono: true; hint: "Inny niż root potrzebuje sudo bez hasła."; onCommitted: (t) => page.set("user", t.trim()) }
            Field { label: "Port SSH"; value: String(page.project.sshPort); numeric: true; onCommitted: (t) => page.set("sshPort", Number(t) || 22) }

            Item {
                width: parent.width; height: keyFlow.height
                Text { y: 8; text: "Klucz SSH"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
                Flow {
                    id: keyFlow
                    x: 170; width: parent.width - 170
                    spacing: 6
                    Repeater {
                        model: [{ name: "Domyślny", path: "" }].concat(page.keys)
                        delegate: HoverButton {
                            id: keyBtn
                            required property var modelData
                            readonly property bool active: (page.project.key || "") === modelData.path
                            width: keyRow.implicitWidth + 24; height: 32; radius: 16
                            baseColor: active ? Theme.accent : Theme.fill
                            color: active ? Theme.accent : (hovered ? Theme.hover : Theme.fill)
                            onClicked: page.set("key", modelData.path)
                            Row {
                                id: keyRow
                                anchors.centerIn: parent
                                spacing: 6
                                Icon { anchors.verticalCenter: parent.verticalCenter; d: LI.key; size: 13; stroke: 2; color: keyBtn.active ? "white" : Theme.text2 }
                                Text { text: keyBtn.modelData.name; color: keyBtn.active ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                            }
                        }
                    }
                    Pill {
                        small: true
                        text: "Nowy klucz"
                        iconPath: Icons.plus
                        onClicked: {
                            const r = Launch.createKey("aster-launch");
                            if (r.ok) { page.keys = Launch.sshKeys(); page.set("key", r.path); page.app.toast("Utworzono klucz " + r.path); }
                            else page.app.toast("Nie udało się utworzyć klucza: " + r.message);
                        }
                    }
                }
            }
            Item {
                readonly property string pub: Launch.publicKey(page.project.key || "")
                visible: pub !== ""
                width: parent.width; height: pubBox.height + 46
                Text { y: 8; text: "Klucz publiczny"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
                Rectangle {
                    id: pubBox
                    x: 170; width: parent.width - 170; height: pubText.implicitHeight + 16; radius: 9
                    color: Theme.fill
                    TextEdit {
                        id: pubText
                        x: 10; y: 8; width: parent.width - 20
                        readOnly: true; selectByMouse: true
                        wrapMode: TextEdit.WrapAnywhere
                        text: parent.parent.pub
                        color: Theme.text; selectionColor: Theme.accentSoft; selectedTextColor: Theme.text
                        font.family: "JetBrains Mono"; font.pixelSize: 11
                    }
                }
                Row {
                    x: 170; y: pubBox.height + 8
                    spacing: 8
                    Pill { small: true; text: "Kopiuj"; iconPath: Icons.copy; onClicked: { Launch.copyText(pubText.text); page.app.toast("Klucz skopiowany — wklej go w panelu serwera (authorized_keys)"); } }
                    Pill { small: true; text: "Dodaj na serwer hasłem…"; iconPath: Icons.terminal; enabled: !!page.project.host; onClicked: Launch.copyKeyInTerminal(page.project.id) }
                }
            }
            Item {
                width: parent.width; height: Math.max(34, probeLabel.implicitHeight)
                Pill {
                    id: probeBtn
                    x: 170
                    text: page.probing ? "Łączę…" : "Sprawdź połączenie"
                    iconPath: Icons.check
                    enabled: !page.probing && !!page.project.host
                    onClicked: { page.probing = true; page.probeText = ""; Launch.probe(page.project.id); }
                }
                Text {
                    id: probeLabel
                    x: probeBtn.x + probeBtn.width + 12; anchors.verticalCenter: probeBtn.verticalCenter
                    width: parent.width - x
                    wrapMode: Text.Wrap
                    text: page.probeText || (page.project.facts ? "Ostatnio: " + page.project.facts.os + " · " + page.app.when(page.project.facts.time) : "Tylko odczyt — nic na serwerze się nie zmieni.")
                    color: page.probeText && !page.probeOk ? Theme.danger : Theme.text2
                    font.family: Theme.font; font.pixelSize: 12
                }
            }
        }

        Card {
            visible: page.ssh
            title: "Domena i HTTPS"
            subtitle: "Z domeną Caddy sam pobierze i odnowi certyfikat Let's Encrypt. Bez domeny strona będzie pod adresem serwera."
            Field {
                label: "Domena"
                value: page.project.domain
                placeholder: "np. sklep.mojadomena.pl"
                mono: true
                onCommitted: (t) => { page.set("domain", t.trim().toLowerCase().replace(/^https?:\/\//, "").replace(/\/.*$/, "")); page.dns = null; }
            }
            Item {
                visible: !!page.project.domain
                width: parent.width; height: Math.max(34, dnsLabel.implicitHeight)
                Pill { id: dnsBtn; x: 170; text: "Sprawdź DNS"; iconPath: LI.dns; onClicked: Launch.checkDns(page.project.id) }
                Text {
                    id: dnsLabel
                    x: dnsBtn.x + dnsBtn.width + 12; anchors.verticalCenter: dnsBtn.verticalCenter
                    width: parent.width - x
                    wrapMode: Text.Wrap
                    text: page.dns ? page.dns.message : "Czy domena wskazuje na ten serwer (rekord A)."
                    color: page.dns && !page.dns.ok ? (Theme.dark ? "#FFC56B" : "#A86200") : Theme.text2
                    font.family: Theme.font; font.pixelSize: 12
                }
            }
            Field {
                visible: !page.project.domain
                label: "Port strony"
                value: String(page.project.publicPort)
                numeric: true
                hint: "Strona pod http://" + (page.project.host || "serwer") + ":" + page.project.publicPort + " (bez HTTPS)."
                onCommitted: (t) => page.set("publicPort", Number(t) || 8080)
            }
            Field {
                label: "Wersje na serwerze"
                value: String(page.project.keep || 5)
                numeric: true
                hint: "Tyle ostatnich wersji zostaje do szybkiego przywrócenia."
                onCommitted: (t) => page.set("keep", Math.max(2, Number(t) || 5))
            }
        }

        // ——— Hosting ———
        Card {
            visible: !page.ssh && !!page.hosting
            title: page.hosting ? page.hosting.name : ""
            subtitle: page.hosting ? "Wdrożenie przez program „" + page.hosting.cli + "” na tym komputerze — Aster Launch prowadzi przez instalację i logowanie." : ""
            Item {
                width: parent.width; height: 36
                Text { y: 8; text: "Program"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
                Row {
                    x: 170; anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Icon { anchors.verticalCenter: parent.verticalCenter; d: page.hosting && page.hosting.installed ? Icons.check : Icons.info; size: 15; stroke: 2; color: page.hosting && page.hosting.installed ? "#2FBF71" : "#F5A623" }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: page.hosting ? (page.hosting.installed ? page.hosting.path : "Brakuje programu " + page.hosting.cli) : ""
                        color: Theme.text; font.family: page.hosting && page.hosting.installed ? "JetBrains Mono" : Theme.font; font.pixelSize: 12
                    }
                    Pill {
                        visible: !!page.hosting && !page.hosting.installed
                        small: true; primary: true
                        enabled: !!page.hosting && page.hosting.npm
                        text: "Zainstaluj"
                        tip: page.hosting ? page.hosting.install : ""
                        onClicked: Launch.installHostingCli(page.project.target)
                    }
                }
            }
            Text {
                visible: !!page.hosting && !page.hosting.installed
                x: 170; width: parent.width - 170; wrapMode: Text.Wrap
                text: page.hosting ? (page.hosting.npm ? "Instalacja dla Twojego konta (bez hasła administratora): " + page.hosting.install
                                                       : "Potrzebny jest Node.js (npm). Zainstaluj go, np. w kontenerze Toolbox, a potem: " + page.hosting.install) : ""
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
            }
            Item {
                visible: !!page.hosting && page.hosting.installed
                width: parent.width; height: 36
                Text { y: 8; text: "Konto"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
                Row {
                    x: 170; anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Text { anchors.verticalCenter: parent.verticalCenter; text: page.loginText || "Sprawdzam…"; color: page.loggedIn ? Theme.text : Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
                    Pill { visible: !page.loggedIn; small: true; primary: true; text: "Zaloguj się"; onClicked: Launch.hostingLogin(page.project.target) }
                    Pill { small: true; text: "Odśwież"; onClicked: Launch.checkHostingLogin(page.project.target) }
                }
            }
            Text {
                visible: page.hostingNote !== ""
                x: 170; width: parent.width - 170; wrapMode: Text.Wrap
                text: page.hostingNote
                color: Theme.text2; font.family: "JetBrains Mono"; font.pixelSize: 11
            }
            Field {
                label: page.project.target === "cloudflare" ? "Projekt Pages" : page.project.target === "vercel" ? "Projekt" : "Strona"
                value: page.project.site
                placeholder: page.project.target === "vercel" ? "powstanie sam" : "nazwa"
                mono: true
                hint: page.hosting ? page.hosting.siteHint : ""
                onCommitted: (t) => page.set("site", t.trim())
            }
            Field {
                label: "Własna domena"
                value: page.project.domain
                placeholder: "nieobowiązkowo"
                mono: true
                hint: "Domenę podłączasz w panelu hostingu; tu służy do sprawdzania strony po wdrożeniu."
                onCommitted: (t) => page.set("domain", t.trim().toLowerCase().replace(/^https?:\/\//, "").replace(/\/.*$/, ""))
            }
        }

        // ——— Usuń ———
        Item {
            width: parent.width; height: 34
            Pill {
                anchors.right: parent.right
                small: true; danger: true
                text: "Usuń projekt z listy"
                onClicked: { Launch.removeProject(page.project.id); page.app.toast("Usunięto z listy — na serwerze nic się nie zmieniło"); }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Folder z kodem i to, co działa na serwerze, zostają bez zmian."
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
            }
        }
    }
}
