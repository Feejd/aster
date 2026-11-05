pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Launch
import "LaunchIcons.js" as LI

// Przegląd projektu: co działa na produkcji, czy strona odpowiada, dokąd wdrażamy, ostatnie wersje
Flickable {
    id: page
    required property var project
    required property var app
    readonly property var check: project.lastCheck || null
    readonly property var history: (project.history || []).slice().reverse()
    readonly property var currentEntry: history.find(h => h.v === project.current) || null
    readonly property var facts: project.facts || null
    readonly property bool ssh: project.target === "ssh"
    readonly property var detected: Launch.detect(project.path)
    property var dns: null
    property bool checking: false
    readonly property var hostingCli: ssh ? null : Launch.hostingInfo(project.target)
    // Ta sama strona dla innego projektu (Loader nie tworzy jej od nowa) — wyniki sprawdzeń od zera
    readonly property string pid: project.id
    onPidChanged: { dns = null; checking = false; if (project.domain) Launch.checkDns(project.id); }

    contentHeight: col.height + 48
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    Component.onCompleted: if (project.domain) Launch.checkDns(project.id)

    Connections {
        target: Launch
        function onDnsChecked(id, result) { if (id === page.project.id) page.dns = result; }
        function onHealthChecked(id, result) { if (id === page.project.id) page.checking = false; }
    }

    function hostingName(t) { return t === "netlify" ? "Netlify" : t === "vercel" ? "Vercel" : t === "cloudflare" ? "Cloudflare Pages" : "Własny serwer"; }

    Column {
        id: col
        x: 28; y: 24
        width: page.width - 56
        spacing: 16

        // ——— Na produkcji ———
        Card {
            Item {
                width: parent.width
                height: page.project.current ? liveCol.height : emptyCol.height

                Column {
                    id: liveCol
                    visible: page.project.current > 0
                    width: parent.width - liveActions.width - 20
                    spacing: 6
                    Text { text: "NA PRODUKCJI"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.6 }
                    Row {
                        spacing: 12
                        Text {
                            text: "v" + page.project.current
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 34; font.weight: Font.Bold; font.letterSpacing: -1
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text {
                                text: page.currentEntry ? "Wdrożona " + page.app.when(page.currentEntry.time) : ""
                                color: Theme.text; font.family: Theme.font; font.pixelSize: 13
                            }
                            Text {
                                visible: !!(page.currentEntry && page.currentEntry.commit)
                                text: page.currentEntry ? (page.currentEntry.commit || "") + "  " + (page.currentEntry.subject || "") + (page.currentEntry.dirty ? "  · z niezatwierdzonymi zmianami" : "") : ""
                                color: Theme.text2; font.family: "JetBrains Mono"; font.pixelSize: 12
                            }
                        }
                    }
                    Item { width: 1; height: 2 }
                    HoverButton {
                        visible: !!page.project.url
                        width: urlRow.implicitWidth + 16; height: 28; radius: 8
                        x: -8
                        onClicked: Launch.openUrl(page.project.url)
                        Row {
                            id: urlRow
                            x: 8; anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            Icon { anchors.verticalCenter: parent.verticalCenter; d: page.project.url.startsWith("https") ? LI.lockOn : LI.link; size: 14; stroke: 2; color: Theme.accentText }
                            Text { text: page.project.url; color: Theme.accentText; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium }
                        }
                    }
                    Row {
                        spacing: 8
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 9; height: 9; radius: 4.5
                            color: page.app.statusColor(page.project)
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.checking ? "Sprawdzam…" : page.check ? page.check.message + " · " + page.app.when(page.check.time) : "Jeszcze nie sprawdzono, czy strona odpowiada"
                            color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                        }
                    }
                }
                Column {
                    id: liveActions
                    visible: page.project.current > 0
                    anchors.right: parent.right
                    spacing: 8
                    Pill {
                        anchors.right: parent.right
                        text: "Sprawdź stronę"
                        iconPath: LI.pulse
                        enabled: !page.checking
                        onClicked: { page.checking = true; Launch.checkHealth(page.project.id); }
                    }
                    Pill {
                        anchors.right: parent.right
                        visible: Launch.previousVersion(page.project.id) > 0
                        text: "Wróć do v" + Launch.previousVersion(page.project.id)
                        iconPath: Icons.undo
                        onClicked: page.app.rollback(Launch.previousVersion(page.project.id))
                    }
                }

                // Jeszcze nie wdrożony: co zostało do zrobienia
                Column {
                    id: emptyCol
                    visible: !page.project.current
                    width: parent.width
                    spacing: 10
                    Text { text: "Jeszcze nie wdrożony"; color: Theme.text; font.family: Theme.font; font.pixelSize: 20; font.weight: Font.Bold; font.letterSpacing: -0.3 }
                    Repeater {
                        model: [
                            { done: true, text: "Projekt rozpoznany: " + page.project.typeName },
                            { done: page.ssh ? !!page.project.host : (page.project.target === "vercel" || !!page.project.site),
                              text: page.ssh ? (page.project.host ? "Serwer: " + page.project.user + "@" + page.project.host : "Podaj serwer albo wybierz hosting") : "Hosting: " + page.hostingName(page.project.target) },
                            page.ssh ? { done: !!page.facts, text: page.facts ? "Połączenie sprawdzone: " + page.facts.os : "Sprawdź połączenie z serwerem" }
                                     : { done: !!(page.hostingCli && page.hostingCli.installed), text: page.hostingCli && page.hostingCli.installed ? "Program " + page.hostingCli.cli + " jest zainstalowany" : "Zainstaluj program " + (page.hostingCli ? page.hostingCli.cli : "") + " i zaloguj się (Cel wdrożenia)" },
                            page.ssh ? { done: !!page.project.domain, text: page.project.domain ? "Domena: " + page.project.domain : "Domena (nieobowiązkowa) — z nią Caddy włączy HTTPS" }
                                     : { done: !!page.project.domain, text: page.project.domain ? "Własna domena: " + page.project.domain : "Własna domena (nieobowiązkowa) — podłączysz ją w panelu hostingu" }
                        ]
                        delegate: Row {
                            id: todo
                            required property var modelData
                            spacing: 10
                            Rectangle {
                                width: 20; height: 20; radius: 10
                                color: todo.modelData.done ? "#2FBF71" : "transparent"
                                border.width: todo.modelData.done ? 0 : 1.5; border.color: Theme.text2
                                Icon { visible: todo.modelData.done; anchors.centerIn: parent; d: Icons.check; size: 12; stroke: 2.6; color: "white" }
                            }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: todo.modelData.text; color: todo.modelData.done ? Theme.text : Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
                        }
                    }
                    Item { width: 1; height: 4 }
                    Row {
                        spacing: 8
                        Pill { text: "Ustaw cel wdrożenia"; iconPath: LI.server; onClicked: page.app.go("target") }
                        Pill { primary: true; text: "Wdróż"; iconPath: LI.rocket; enabled: !Launch.preparing; onClicked: page.app.deploy() }
                    }
                }
            }
        }

        // ——— Projekt i cel ———
        Row {
            width: parent.width
            spacing: 16
            Card {
                id: projCard
                width: (parent.width - 16) / 2
                height: Math.max(naturalHeight, targetCard.naturalHeight)
                title: "Projekt"
                subtitle: page.detected.notes ? page.detected.notes.join(" ") : ""
                Repeater {
                    model: [
                        ["Typ", page.project.typeName],
                        ["Budowanie", page.project.build || "—"],
                        ["Na serwer trafia", page.project.output ? "folder " + page.project.output : (page.project.type === "static" ? "cały folder" : "folder bez .git, node_modules, .venv")],
                        ["Uruchomienie", page.project.type === "node" || page.project.type === "python" ? page.project.start : page.project.type === "static" ? "Caddy podaje pliki" : "kontener"],
                        ["Port aplikacji", page.project.type === "static" ? "—" : String(page.project.port)]
                    ]
                    delegate: InfoRow { required property var modelData; label: modelData[0]; value: modelData[1]; mono: modelData[0] !== "Typ" && modelData[0] !== "Na serwer trafia" }
                }
            }
            Card {
                id: targetCard
                width: (parent.width - 16) / 2
                height: Math.max(naturalHeight, projCard.naturalHeight)
                title: "Cel wdrożenia"
                subtitle: page.ssh ? (page.facts ? page.facts.os + " · " + page.facts.arch : "Serwer jeszcze nie sprawdzony") : ""
                Column {
                    id: targetCol
                    width: parent.width
                    spacing: 10
                    InfoRow { label: page.ssh ? "Serwer" : "Hosting"; value: page.ssh ? (page.project.host ? page.project.user + "@" + page.project.host + (page.project.sshPort !== 22 ? ":" + page.project.sshPort : "") : "—") : page.hostingName(page.project.target); mono: page.ssh }
                    InfoRow {
                        visible: page.ssh
                        label: "Uruchomienie"
                        value: page.project.type === "static" ? "Caddy" : page.project.type === "docker" || page.project.type === "compose"
                               ? (page.facts && page.facts.podman ? "kontener podman" : page.facts && page.facts.docker ? "kontener docker" : "kontener")
                               : "usługa systemd"
                    }
                    InfoRow { visible: !page.ssh; label: "Strona"; value: page.project.site || "—"; mono: true }
                    InfoRow { label: "Domena"; value: page.project.domain || (page.ssh ? "bez domeny (port " + page.project.publicPort + ")" : "adres od hostingu") }
                    Row {
                        visible: !!page.project.domain && !!page.dns
                        width: parent.width
                        spacing: 8
                        Icon { id: dnsIcon; d: page.dns && page.dns.ok ? Icons.check : Icons.info; size: 15; stroke: 2; color: page.dns && page.dns.ok ? "#2FBF71" : "#F5A623" }
                        Text { width: parent.width - dnsIcon.width - 8; wrapMode: Text.Wrap; text: page.dns ? page.dns.message : ""; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
                    }
                    Row {
                        spacing: 8
                        Pill { small: true; text: "Zmień"; onClicked: page.app.go("target") }
                        Pill { small: true; visible: !!page.project.domain; text: "Sprawdź DNS"; iconPath: LI.dns; onClicked: Launch.checkDns(page.project.id) }
                    }
                }
            }
        }

        // ——— Ostatnie wersje ———
        Card {
            visible: page.history.length > 0
            title: "Ostatnie wersje"
            Repeater {
                model: page.history.slice(0, 3)
                delegate: VersionRow {
                    required property var modelData
                    entry: modelData
                    project: page.project
                    app: page.app
                }
            }
            Pill { small: true; visible: page.history.length > 3; text: "Cała historia (" + page.history.length + ")"; onClicked: page.app.go("history") }
        }
    }

    component InfoRow: Item {
        id: ir
        property string label
        property string value
        property bool mono: false
        width: parent ? parent.width : 0
        height: Math.max(18, valueText.implicitHeight)
        Text { width: 120; elide: Text.ElideRight; text: ir.label; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
        Text {
            id: valueText
            x: 124; width: parent.width - 124
            wrapMode: Text.WrapAnywhere; maximumLineCount: 2; elide: Text.ElideRight
            text: ir.value
            color: Theme.text; font.family: ir.mono ? "JetBrains Mono" : Theme.font; font.pixelSize: ir.mono ? 12 : 13
        }
    }
}
