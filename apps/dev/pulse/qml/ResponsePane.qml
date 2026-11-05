pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Dialogs
import Aster.Ui
import Aster.Pulse

// Odpowiedź: kod, czas i rozmiar; Podgląd (drzewo JSON ze zwijaniem i wyszukiwaniem, tekst, obraz),
// Surowa treść i Nagłówki. Przed pierwszym wysłaniem — podpowiedź.
Item {
    id: rs
    property string tab: "pretty"
    property bool busy: Pulse.busy
    readonly property var r: Pulse.response
    readonly property bool has: !!r.has
    signal rowMenu(int row, real x, real y)
    signal toast(string text)

    function statusColor(code) {
        if (!code) return "#E5484D";
        if (code < 300) return "#16A34A";
        if (code < 400) return "#2563EB";
        if (code < 500) return "#D97706";
        return "#DC2626";
    }
    function size(n) {
        if (n === undefined) return "";
        if (n < 1024) return n + " B";
        if (n < 1024 * 1024) return (n / 1024).toFixed(n < 10240 ? 1 : 0).replace(".", ",") + " kB";
        return (n / 1048576).toFixed(1).replace(".", ",") + " MB";
    }
    function time(ms) {
        if (ms === undefined) return "";
        return ms < 1000 ? ms + " ms" : (ms / 1000).toFixed(2).replace(".", ",") + " s";
    }
    function focusSearch() { tab = "pretty"; search.focusEnd(); }

    Connections {
        target: Pulse
        function onResponseChanged() {
            if (!rs.has) return;
            rawView.setText(Pulse.responseText);
            prettyText.setText(Pulse.responseText);
            search.setText("");
        }
    }

    // ——— Pasek stanu ———
    Item {
        id: statusBar
        x: 20; width: parent.width - 40; height: 46
        visible: rs.has

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: statusText.implicitWidth + 20; height: 26; radius: 13
                color: Qt.rgba(Qt.color(rs.statusColor(rs.r.status)).r, Qt.color(rs.statusColor(rs.r.status)).g, Qt.color(rs.statusColor(rs.r.status)).b, Theme.dark ? 0.28 : 0.14)
                Text {
                    id: statusText
                    anchors.centerIn: parent
                    text: rs.r.status ? rs.r.status + (rs.r.statusText ? " " + rs.r.statusText : "") : "Błąd"
                    color: Theme.dark ? Qt.lighter(rs.statusColor(rs.r.status), 1.5) : rs.statusColor(rs.r.status)
                    font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Bold
                }
            }
            Meta { icon: "clock"; text: rs.time(rs.r.timeMs); visible: rs.r.timeMs !== undefined && !!rs.r.status }
            Meta { icon: "download"; text: rs.size(rs.r.size); visible: !!rs.r.status }
            Meta { icon: "warning"; text: "Brak wartości: " + (rs.r.unresolved || []).join(", "); visible: (rs.r.unresolved || []).length > 0; warn: true }
        }
        TabBar {
            id: tabs
            anchors.right: actions.left; anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            visible: !!rs.r.status
            current: rs.tab
            tabs: [
                { id: "pretty", label: "Podgląd" },
                { id: "raw", label: "Surowa" },
                { id: "headers", label: "Nagłówki", count: (rs.r.headers || []).length }
            ]
            onPicked: (id) => rs.tab = id
        }
        Row {
            id: actions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: !!rs.r.status
            spacing: 2
            ToolBtn { icon: "copy"; tip: "Kopiuj treść"; onClicked: { Pulse.copy(Pulse.responseText); rs.toast("Skopiowano treść odpowiedzi"); } }
            ToolBtn { icon: "download"; tip: "Zapisz treść do pliku…"; onClicked: saveDialog.open() }
        }
    }
    Rectangle { visible: rs.has; x: 20; y: statusBar.height; width: parent.width - 40; height: 1; color: Theme.line }

    FileDialog {
        id: saveDialog
        title: "Zapisz odpowiedź"
        fileMode: FileDialog.SaveFile
        currentFile: "odpowiedz." + (rs.r.kind === "json" ? "json" : rs.r.kind === "html" ? "html" : rs.r.kind === "image" ? (rs.r.contentType || "image/png").split("/")[1].split(";")[0] : "txt")
        onAccepted: Pulse.saveResponse(selectedFile)
    }

    Item {
        id: body
        x: 20; y: statusBar.height + 10
        width: parent.width - 40; height: parent.height - y - 14
        visible: rs.has && !!rs.r.status

        // ——— Podgląd ———
        Item {
            anchors.fill: parent
            visible: rs.tab === "pretty"

            // Drzewo JSON
            Item {
                anchors.fill: parent
                visible: rs.r.kind === "json"
                Row {
                    id: treeTools
                    width: parent.width
                    spacing: 6
                    Field {
                        id: search
                        width: Math.min(320, parent.width - toolsRight.width - 20)
                        height: 30
                        vars: false
                        placeholder: "Szukaj w odpowiedzi (Ctrl+F)"
                        leftPad: 30
                        onEdited: Pulse.tree.filter = text
                        Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; d: Icons.search; size: 14; color: Theme.text2 }
                        Keys.onEscapePressed: { setText(""); Pulse.tree.filter = ""; }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Pulse.tree.filter !== ""
                        text: Pulse.tree.matches === 0 ? "Brak trafień" : Pulse.tree.matches + (Pulse.tree.matches === 1 ? " trafienie" : Pulse.tree.matches % 10 >= 2 && Pulse.tree.matches % 10 <= 4 && (Pulse.tree.matches % 100 < 12 || Pulse.tree.matches % 100 > 14) ? " trafienia" : " trafień")
                        color: Pulse.tree.matches === 0 ? Theme.danger : Theme.text2
                        font.family: Theme.font; font.pixelSize: 12
                    }
                }
                Row {
                    id: toolsRight
                    anchors.right: parent.right
                    spacing: 2
                    ToolBtn { width: 30; height: 30; icon: "plus"; tip: "Rozwiń wszystko"; onClicked: Pulse.tree.expandAll() }
                    ToolBtn { width: 30; height: 30; icon: "minus"; tip: "Zwiń wszystko"; onClicked: Pulse.tree.collapseAll() }
                }
                Rectangle {
                    y: 40; width: parent.width; height: parent.height - y
                    radius: 10
                    color: Theme.fill
                    clip: true
                    ListView {
                        id: tree
                        anchors.fill: parent
                        anchors.margins: 6
                        model: Pulse.tree
                        boundsBehavior: Flickable.StopAtBounds
                        reuseItems: true
                        cacheBuffer: 400
                        delegate: TreeRow {}
                    }
                    Rectangle {
                        visible: tree.contentHeight > tree.height
                        x: parent.width - 6; width: 4; radius: 2
                        y: 6 + tree.visibleArea.yPosition * (tree.height)
                        height: Math.max(24, tree.visibleArea.heightRatio * tree.height)
                        color: Theme.text2
                        opacity: tree.moving ? 0.5 : 0.25
                    }
                }
            }
            CodeArea {
                id: prettyText
                anchors.fill: parent
                visible: rs.r.kind === "text" || rs.r.kind === "html" || rs.r.kind === "xml"
                readOnly: true
                json: false
                numbers: false
                wrap: true
            }
            Column {
                anchors.centerIn: parent
                spacing: 12
                visible: rs.r.kind === "image"
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(body.width - 40, Math.max(64, img.implicitWidth)) ; height: Math.min(body.height - 60, Math.max(64, img.implicitHeight))
                    radius: 10; color: Theme.fill
                    Image {
                        id: img
                        anchors.centerIn: parent
                        width: Math.min(parent.width - 16, implicitWidth * 4); height: Math.min(parent.height - 16, implicitHeight * 4)
                        fillMode: Image.PreserveAspectFit
                        smooth: implicitWidth > 64
                        source: rs.r.dataUrl || ""
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: (rs.r.contentType || "") + (img.implicitWidth ? " · " + img.implicitWidth + "×" + img.implicitHeight + " px" : "")
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                }
            }
            Empty {
                visible: rs.r.kind === "binary" || rs.r.kind === "empty"
                icon: rs.r.kind === "empty" ? "check" : "archive"
                title: rs.r.kind === "empty" ? "Odpowiedź bez treści" : "Odpowiedź binarna"
                detail: rs.r.kind === "empty" ? "Serwer odpowiedział kodem " + rs.r.status + " i nie wysłał treści." : (rs.r.contentType || "nieznany typ") + " · " + rs.size(rs.r.size) + " — zapisz ją do pliku, by otworzyć w innym programie."
                action: rs.r.kind === "binary" ? "Zapisz do pliku…" : ""
                onAct: saveDialog.open()
            }
        }

        // ——— Surowa ———
        CodeArea {
            id: rawView
            anchors.fill: parent
            visible: rs.tab === "raw"
            readOnly: true
            json: rs.r.kind === "json"
        }
        Text {
            visible: rs.tab === "raw" && !!rs.r.viewTruncated
            anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 10
            text: "Pokazano początek — całość zapisz do pliku"
            color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
        }

        // ——— Nagłówki ———
        Flickable {
            anchors.fill: parent
            visible: rs.tab === "headers"
            contentHeight: headersCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: headersCol
                width: parent.width
                spacing: 0
                Caption { text: "Odpowiedź" }
                Repeater { model: rs.r.headers || []; delegate: HeaderRow {} }
                Item { width: 1; height: 14 }
                Caption { text: "Wysłane" }
                Repeater { model: rs.r.requestHeaders || []; delegate: HeaderRow {} }
                Item { width: 1; height: 10 }
                Text {
                    width: parent.width
                    wrapMode: Text.WrapAnywhere
                    text: rs.r.method + " " + rs.r.url + (rs.r.redirectedTo ? "\n→ przekierowano do " + rs.r.redirectedTo : "")
                    color: Theme.text2; font.family: "JetBrains Mono"; font.pixelSize: 11
                }
            }
        }
    }

    // ——— Stany bez odpowiedzi ———
    Empty {
        visible: !rs.has && !rs.busy
        icon: "pulse"
        title: "Tu pojawi się odpowiedź"
        detail: "Wpisz adres i naciśnij Ctrl+Enter. Zmienne jak {{baseUrl}} biorą się z wybranego środowiska."
    }
    Column {
        anchors.centerIn: parent
        visible: rs.busy
        spacing: 14
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 44; height: 44
            Rectangle { anchors.fill: parent; radius: 22; color: "transparent"; border.width: 3; border.color: Theme.fill }
            Rectangle {
                width: 10; height: 10; radius: 5; color: Theme.accent
                x: 22 + 17 * Math.cos(spin.angle) - 5; y: 22 + 17 * Math.sin(spin.angle) - 5
            }
            QtObject { id: spin; property real angle: 0 }
            NumberAnimation { target: spin; property: "angle"; from: 0; to: Math.PI * 2; duration: 900; loops: Animation.Infinite; running: rs.busy }
        }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Czekam na odpowiedź…"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
    }
    Empty {
        visible: rs.has && !rs.r.status && !rs.busy
        y: statusBar.height
        height: parent.height - statusBar.height
        icon: "alertCircle"
        iconColor: Theme.danger
        title: rs.r.error === "Anulowano" ? "Anulowano" : "Nie udało się wysłać zapytania"
        detail: (rs.r.error || "") + (rs.r.url ? "\n" + rs.r.url : "")
    }

    // ——— Elementy ———
    component Meta: Row {
        id: meta
        property string icon
        property string text
        property bool warn: false
        spacing: 5
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons[meta.icon] || ""; size: 13; color: meta.warn ? "#D97706" : Theme.text2 }
        Text { anchors.verticalCenter: parent.verticalCenter; text: meta.text; color: meta.warn ? (Theme.dark ? "#F5B76A" : "#B45309") : Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.features: { "tnum": 1 } }
    }
    component Caption: Text {
        height: 26
        verticalAlignment: Text.AlignVCenter
        color: Theme.text2
        font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.6
    }
    component HeaderRow: Item {
        id: hr
        required property var modelData
        width: headersCol.width
        height: Math.max(28, val.implicitHeight + 10)
        Rectangle { width: parent.width; height: 1; color: Theme.line }
        Text {
            id: hk
            y: 6; width: Math.min(240, parent.width * 0.35)
            text: hr.modelData[0]
            elide: Text.ElideRight
            color: Theme.text2
            font.family: "JetBrains Mono"; font.pixelSize: 12
        }
        TextEdit {
            id: val
            x: hk.width + 12; y: 6; width: parent.width - x
            readOnly: true; selectByMouse: true
            wrapMode: TextEdit.WrapAnywhere
            text: hr.modelData[1]
            color: Theme.text; selectionColor: Theme.accentSoft; selectedTextColor: Theme.text
            font.family: "JetBrains Mono"; font.pixelSize: 12
        }
    }
    component Empty: Column {
        id: em
        property string icon
        property color iconColor: Theme.accentText
        property string title
        property string detail
        property string action
        signal act()
        anchors.centerIn: parent
        width: Math.min(420, rs.width - 60)
        spacing: 8
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 56; height: 56; radius: 10
            color: Theme.fill
            Icon { anchors.centerIn: parent; d: Icons[em.icon] || ""; size: 26; stroke: 1.9; color: em.iconColor }
        }
        Item { width: 1; height: 4 }
        Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: em.title; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold }
        Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; text: em.detail; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.2 }
        Item { width: 1; height: 4; visible: em.action !== "" }
        Pill { visible: em.action !== ""; anchors.horizontalCenter: parent.horizontalCenter; text: em.action; onClicked: em.act() }
    }
    component TreeRow: Rectangle {
        id: tr
        required property int index
        required property int depth
        required property string key
        required property string value
        required property string kind
        required property bool expandable
        required property bool expanded
        required property int count
        required property bool match
        required property bool indexKey
        required property bool last
        width: ListView.view ? ListView.view.width : 0
        height: 24
        radius: 6
        color: match ? Theme.accentSoft : rowArea.containsMouse ? Theme.hover : "transparent"
        readonly property color keyColor: Theme.dark ? "#8CB4FF" : "#1F4FC8"
        readonly property color valueColor: kind === "string" ? (Theme.dark ? "#9FE09A" : "#1A7F37")
                                           : kind === "number" ? (Theme.dark ? "#F5B76A" : "#B35A00")
                                           : kind === "bool" || kind === "null" ? (Theme.dark ? "#E39CF5" : "#8E2BB8") : Theme.text2
        Icon {
            visible: tr.expandable
            x: 6 + tr.depth * 16; anchors.verticalCenter: parent.verticalCenter
            d: Icons.chevronRight; size: 12; stroke: 2.2; color: Theme.text2
            rotation: tr.expanded ? 90 : 0
            Behavior on rotation { NumberAnimation { duration: 120 } }
        }
        Text {
            id: keyText
            x: 22 + tr.depth * 16; anchors.verticalCenter: parent.verticalCenter
            text: tr.key === "" ? "" : (tr.indexKey ? tr.key : "\"" + tr.key + "\"") + ":"
            color: tr.indexKey ? Theme.text2 : tr.keyColor
            font.family: "JetBrains Mono"; font.pixelSize: 12
        }
        Text {
            x: keyText.x + keyText.implicitWidth + (tr.key === "" ? 0 : 8)
            width: parent.width - x - (countText.visible ? countText.implicitWidth + 16 : 8)
            anchors.verticalCenter: parent.verticalCenter
            text: tr.expandable && tr.expanded ? (tr.kind === "object" ? "{" : "[") : tr.value
            elide: Text.ElideRight
            color: tr.valueColor
            font.family: "JetBrains Mono"; font.pixelSize: 12
        }
        Text {
            id: countText
            visible: tr.expandable
            anchors.right: parent.right; anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: tr.kind === "object" ? tr.count + (tr.count === 1 ? " pole" : tr.count % 10 >= 2 && tr.count % 10 <= 4 && (tr.count % 100 < 12 || tr.count % 100 > 14) ? " pola" : " pól")
                                       : tr.count + (tr.count === 1 ? " element" : tr.count % 10 >= 2 && tr.count % 10 <= 4 && (tr.count % 100 < 12 || tr.count % 100 > 14) ? " elementy" : " elementów")
            color: Theme.text2; opacity: 0.8
            font.family: Theme.font; font.pixelSize: 11
        }
        MouseArea {
            id: rowArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (m) => {
                if (m.button === Qt.RightButton) { const p = mapToItem(rs, m.x, m.y); rs.rowMenu(tr.index, p.x, p.y); }
                else if (tr.expandable) Pulse.tree.toggle(tr.index);
            }
        }
    }
}
