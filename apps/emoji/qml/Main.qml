pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import Aster.Ui
import Aster.Emoji

// Panel emoji i znaków (Win+. jak w Windows): emoji z wyszukiwaniem po polsku (bez ogonków też),
// ostatnio używane, odcień skóry, kaomoji i symbole. Klik wstawia znak do programu, który był aktywny.
Window {
    id: win
    width: 392 + 2 * m
    height: 476 + 2 * m
    color: "transparent"
    flags: Qt.FramelessWindowHint
    title: "Emoji"
    visible: false

    readonly property int m: 24
    readonly property real r: 20

    property string tab: "emoji"                   // emoji | kaomoji | symbols
    property string query: search.text.trim()
    property string hoverChar: ""
    property string hoverName: ""
    property bool toneOpen: false
    property string copiedText: ""

    function showPanel() {
        tab = "emoji";
        search.text = "";
        toneOpen = false;
        copiedText = "";
        list.positionViewAtBeginning();
        win.show();
        win.requestActivate();
        search.forceActiveFocus();
    }
    function hidePanel() { win.hide(); }
    Connections {
        target: Emoji
        function onToggleRequested() { if (win.visible) win.hidePanel(); else win.showPanel(); }
        function onHideRequested() { win.hidePanel(); }
        function onCopied(text) { win.copiedText = text; copiedTimer.restart(); }
    }
    Timer { id: copiedTimer; interval: 3000; onTriggered: win.copiedText = "" }
    // Kliknięcie poza panelem — chowa (jak menu)
    onActiveChanged: if (!active && visible && !WindowEffects.preview) hideTimer.restart()
    Timer { id: hideTimer; interval: 120; onTriggered: if (!win.active) win.hidePanel() }

    function withTone(item) {
        const tones = item.t;
        return Emoji.tone > 0 && tones.length === 5 ? tones[Emoji.tone - 1] : item.c;
    }
    function pick(text, remember) { Emoji.insert(text, remember); }

    // ——— Wiersze listy emoji: nagłówki grup i rzędy po `cols` znaków ———
    readonly property int cols: 9
    readonly property real cell: (list.width) / cols
    readonly property var allItems: {
        const out = [];
        for (const g of Emoji.groups) for (const e of g.emoji) out.push(e);
        return out;
    }
    readonly property var byChar: {
        const m = {};
        for (const e of allItems) m[e.c] = e;
        return m;
    }
    readonly property var rows: {
        const out = [];
        const push = (title, gid, items) => {
            if (items.length === 0) return;
            out.push({ header: title, gid: gid });
            for (let i = 0; i < items.length; i += cols) out.push({ items: items.slice(i, i + cols), gid: gid });
        };
        if (query) {
            const words = Emoji.fold(query).split(/\s+/);
            push("Wyniki", "search", allItems.filter(e => words.every(w => e.s.indexOf(w) >= 0)));
            return out;
        }
        const recent = Emoji.recent.map(c => byChar[c] || { c: c, n: Emoji.nameOf(c) || c, t: [], s: "" }).slice(0, cols * 2);
        push("Ostatnio używane", "recent", recent);
        for (const g of Emoji.groups) push(g.name, g.id, g.emoji);
        return out;
    }
    function jumpTo(gid) {
        for (let i = 0; i < rows.length; ++i)
            if (rows[i].gid === gid) { list.positionViewAtIndex(i, ListView.Beginning); return; }
    }
    readonly property string currentGroup: {
        const i = list.indexAt(10, list.contentY + 4);
        return i >= 0 && rows[i] ? rows[i].gid : "";
    }

    // ——— Okno ———
    function updateEffects() {
        WindowEffects.setBlur(win, Qt.rect(m, m, frame.width, frame.height), r);
        WindowEffects.setInputRegion(win, Qt.rect(m, m, frame.width, frame.height));
    }
    onVisibleChanged: if (visible) effectsTimer.restart()
    Timer { id: effectsTimer; interval: 16; onTriggered: win.updateEffects() }

    WindowShadow { window: win; frame: frame; radius: win.r }

    Rectangle {
        id: frame
        x: win.m; y: win.m
        width: win.width - 2 * win.m
        height: win.height - 2 * win.m
        radius: win.r
        color: Theme.glass
        border.width: 1; border.color: Theme.edge
        WindowSheen { window: win; radius: win.r }

        Keys.onEscapePressed: win.hidePanel()

        // Zakładki: emoji, kaomoji, symbole
        Row {
            id: tabs
            x: 12; y: 10
            spacing: 4
            Repeater {
                model: [["emoji", "😊", "Emoji"], ["kaomoji", ";-)", "Kaomoji"], ["symbols", "Ω", "Symbole"]]
                delegate: HoverButton {
                    id: tb
                    required property var modelData
                    readonly property bool on: win.tab === modelData[0]
                    width: 40; height: 34; radius: 9
                    baseColor: on ? Theme.accentSoft : "transparent"
                    onClicked: { win.tab = tb.modelData[0]; search.forceActiveFocus(); }
                    Text {
                        anchors.centerIn: parent
                        text: tb.modelData[1]
                        color: tb.on ? Theme.accentText : Theme.text
                        font.family: tb.modelData[0] === "emoji" ? "Noto Color Emoji" : Theme.font
                        font.pixelSize: tb.modelData[0] === "emoji" ? 17 : 14; font.weight: Font.DemiBold
                    }
                    Rectangle {
                        visible: tb.on
                        anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom
                        width: 16; height: 3; radius: 1.5; color: Theme.accent
                    }
                }
            }
        }
        // Odcień skóry
        HoverButton {
            id: toneBtn
            visible: win.tab === "emoji"
            anchors.right: closeBtn.left; anchors.rightMargin: 4
            y: 10; width: 36; height: 34; radius: 9
            onClicked: win.toneOpen = !win.toneOpen
            Text {
                anchors.centerIn: parent
                text: ["✋", "✋🏻", "✋🏼", "✋🏽", "✋🏾", "✋🏿"][Emoji.tone]
                font.family: "Noto Color Emoji"; font.pixelSize: 17
            }
        }
        HoverButton {
            id: closeBtn
            anchors.right: parent.right; anchors.rightMargin: 10
            y: 10; width: 34; height: 34; radius: 9
            onClicked: win.hidePanel()
            Icon { anchors.centerIn: parent; d: Icons.close; size: 14; stroke: 2; color: Theme.text2 }
        }

        // Szukaj
        Rectangle {
            id: searchBox
            x: 12; y: 52
            width: parent.width - 24; height: 36; radius: 10
            color: Theme.fill
            border.width: search.activeFocus ? 2 : 0; border.color: Theme.accent
            Icon { x: 11; anchors.verticalCenter: parent.verticalCenter; d: Icons.search; size: 15; color: Theme.text2 }
            TextInput {
                id: search
                x: 34; width: parent.width - 46
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.text; selectionColor: Theme.accentSoft; selectedTextColor: Theme.text
                font.family: Theme.font; font.pixelSize: 13
                clip: true
                onTextChanged: if (win.tab !== "emoji") win.tab = "emoji"
                Keys.onEscapePressed: { if (text) text = ""; else win.hidePanel(); }
                Keys.onReturnPressed: { const r = win.rows[1]; if (r && r.items) win.pick(win.withTone(r.items[0]), true); }
                Keys.onDownPressed: list.flick(0, -800)
                Text {
                    visible: !parent.text
                    text: win.tab === "emoji" ? "Szukaj emoji, np. serce, kot, uśmiech" : "Szukaj emoji"
                    color: Theme.text2; font: parent.font
                }
            }
        }

        // ——— Emoji ———
        Item {
            id: emojiTab
            visible: win.tab === "emoji"
            x: 8; y: searchBox.y + searchBox.height + 6
            width: parent.width - 16
            height: parent.height - y - footer.height - (groupBar.visible ? groupBar.height : 0)

            ListView {
                id: list
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: win.rows
                cacheBuffer: 400
                delegate: Item {
                    id: row
                    required property var modelData
                    width: ListView.view.width
                    height: modelData.header ? 30 : win.cell
                    Text {
                        visible: !!row.modelData.header
                        x: 6; anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                        text: row.modelData.header || ""
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                    }
                    Row {
                        visible: !row.modelData.header
                        Repeater {
                            model: row.modelData.items || []
                            delegate: HoverButton {
                                id: cellBtn
                                required property var modelData
                                readonly property string ch: win.withTone(modelData)
                                width: win.cell; height: win.cell; radius: 8
                                onClicked: win.pick(cellBtn.ch, true)
                                onHoveredChanged: if (hovered) { win.hoverChar = cellBtn.ch; win.hoverName = cellBtn.modelData.n; }
                                Text {
                                    anchors.centerIn: parent
                                    text: cellBtn.ch
                                    font.family: "Noto Color Emoji"; font.pixelSize: 24
                                    renderType: Text.QtRendering
                                }
                            }
                        }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: win.query !== "" && win.rows.length === 0
                    text: "Nic nie znaleziono"
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
                }
            }
        }

        // Grupy (przewija do początku grupy)
        Row {
            id: groupBar
            visible: win.tab === "emoji" && !win.query
            anchors.bottom: footer.top
            x: 8; height: 40
            Repeater {
                model: [["recent", "🕘"], ["smileys", "😀"], ["people", "👋"], ["nature", "🐻"], ["food", "🍕"],
                        ["travel", "🚗"], ["activities", "⚽"], ["objects", "💡"], ["symbols", "❤️"], ["flags", "🏳️"]]
                delegate: HoverButton {
                    id: gb
                    required property var modelData
                    readonly property bool on: win.currentGroup === modelData[0]
                    width: (frame.width - 16) / 10; height: 36; radius: 8
                    visible: modelData[0] !== "recent" || Emoji.recent.length > 0
                    onClicked: win.jumpTo(gb.modelData[0])
                    Text { anchors.centerIn: parent; text: gb.modelData[1]; font.family: "Noto Color Emoji"; font.pixelSize: 17; opacity: gb.on ? 1 : 0.55 }
                    Rectangle { visible: gb.on; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; width: 14; height: 3; radius: 1.5; color: Theme.accent }
                }
            }
        }

        // ——— Kaomoji i symbole ———
        Flickable {
            visible: win.tab !== "emoji"
            x: 12; y: searchBox.y + searchBox.height + 6
            width: parent.width - 24
            height: parent.height - y - footer.height
            contentHeight: textCol.implicitHeight + 10
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: textCol
                width: parent.width
                spacing: 4
                Repeater {
                    model: win.tab === "kaomoji" ? Lists.kaomoji : Lists.symbols
                    delegate: Column {
                        id: sect
                        required property var modelData
                        width: textCol.width
                        spacing: 2
                        Text {
                            topPadding: 8; bottomPadding: 4; leftPadding: 2
                            text: sect.modelData.name
                            color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                        }
                        Flow {
                            width: parent.width
                            Repeater {
                                model: sect.modelData.items
                                delegate: HoverButton {
                                    id: sym
                                    required property string modelData
                                    readonly property bool wide: win.tab === "kaomoji"
                                    width: wide ? Math.max(textCol.width / 3, symText.implicitWidth + 16) : textCol.width / 10
                                    height: wide ? 38 : textCol.width / 10
                                    radius: 8
                                    onClicked: win.pick(sym.modelData, false)
                                    Text {
                                        id: symText
                                        anchors.centerIn: parent
                                        text: sym.modelData
                                        color: Theme.text
                                        font.family: Theme.font; font.pixelSize: sym.wide ? 13 : 19
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Wybór odcienia skóry
        Rectangle {
            visible: win.toneOpen
            anchors.right: parent.right; anchors.rightMargin: 10
            y: 48
            width: toneRow.implicitWidth + 12; height: 46; radius: 12
            color: Theme.surface
            border.width: 1; border.color: Theme.edge
            z: 10
            Row {
                id: toneRow
                anchors.centerIn: parent
                spacing: 2
                Repeater {
                    model: ["✋", "✋🏻", "✋🏼", "✋🏽", "✋🏾", "✋🏿"]
                    delegate: HoverButton {
                        id: toneOpt
                        required property string modelData
                        required property int index
                        width: 36; height: 36; radius: 8
                        baseColor: Emoji.tone === index ? Theme.accentSoft : "transparent"
                        onClicked: { Emoji.tone = toneOpt.index; win.toneOpen = false; }
                        Text { anchors.centerIn: parent; text: toneOpt.modelData; font.family: "Noto Color Emoji"; font.pixelSize: 20 }
                    }
                }
            }
        }

        // Stopka: podgląd emoji pod kursorem albo „skopiowano”
        Item {
            id: footer
            anchors.bottom: parent.bottom
            width: parent.width; height: 44
            Rectangle { width: parent.width; height: 1; color: Theme.line }
            Text {
                id: footChar
                x: 16; anchors.verticalCenter: parent.verticalCenter
                text: win.copiedText || win.hoverChar
                font.family: "Noto Color Emoji"; font.pixelSize: 20
            }
            Text {
                x: footChar.text ? 50 : 16; width: parent.width - x - 14
                anchors.verticalCenter: parent.verticalCenter
                text: win.copiedText ? "Skopiowano — wklej Ctrl+V" : (win.hoverName || "Wybierz emoji, aby je wstawić")
                elide: Text.ElideRight
                color: win.copiedText ? Theme.accentText : Theme.text2
                font.family: Theme.font; font.pixelSize: 12
            }
        }
    }

    // Do testów (ASTER_OPEN, kroki po „;”): show | search:tekst | tab:kaomoji | tone | jump:food
    function testOpen(what) {
        if (what === "show") showPanel();
        else if (what.startsWith("search:")) search.text = what.substring(7);
        else if (what.startsWith("tab:")) tab = what.substring(4);
        else if (what === "tone") toneOpen = true;
        else if (what.startsWith("jump:")) jumpTo(what.substring(5));
        else if (what.startsWith("hover:")) { hoverChar = what.substring(6); hoverName = Emoji.nameOf(hoverChar); }
    }
}
