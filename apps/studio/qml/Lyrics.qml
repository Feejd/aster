pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Studio

// Zakładka Tekst: pisanie (Pisz), czytanie z rymami i bieżącym wersem (Czytaj) oraz czas wersów —
// od którego taktu, co ile taktów albo „wyklikane” w trakcie grania (↓ na początku każdego wersu)
Item {
    id: ly
    property string mode: "write"
    // Nowy albo otwarty projekt: bez tekstu — od razu pisanie, z tekstem — czytanie
    function resetMode() { mode = Studio.lyrics === "" ? "write" : "read"; }
    Component.onCompleted: resetMode()
    property bool prompter: true            // prompter nad osią czasu w trakcie nagrywania
    property int syncIndex: -1              // ustawianie w trakcie grania: który wers (kolejny) czeka na ↓
    readonly property bool syncing: syncIndex >= 0
    readonly property var lines: Studio.lyricLines
    readonly property var content: lines.filter((l) => l.kind === "line")
    readonly property int current: (Studio.playing || Studio.recording) && lines.length >= 0 ? Studio.lyricAt(Studio.position) : -1
    readonly property real spb: 60 / Studio.bpm

    // ↓ w trakcie ustawiania: kolejny wers zaczyna się teraz
    function tap() {
        if (!syncing || syncIndex >= content.length)
            return;
        Studio.markLyric(content[syncIndex].line, Studio.position);
        syncIndex = syncIndex + 1 < content.length ? syncIndex + 1 : -1;
    }
    function startSync() {
        if (content.length === 0)
            return;
        syncIndex = 0;
        // Od taktu przed pierwszym wersem — jest czas, żeby się przygotować
        Studio.stop();
        Studio.seek(Math.max(0, content[0].beat * spb - Studio.beatsPerBar * spb));
        Studio.play();
    }
    Connections {
        target: Studio
        function onTransportChanged() { if (!Studio.playing && !Studio.recording) ly.syncIndex = -1; }
        function onProjectChanged() { ly.syncIndex = -1; ly.resetMode(); }
    }

    Item {
        id: head
        width: parent.width; height: 50
        Segmented {
            x: 14; anchors.verticalCenter: parent.verticalCenter
            model: [{ label: "Pisz", value: "write" }, { label: "Czytaj", value: "read" }]
            value: ly.mode
            onPicked: (v) => ly.mode = v
        }
        Text {
            anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
            text: ly.content.length === 1 ? "1 wers" : ly.content.length + (ly.content.length % 10 >= 2 && ly.content.length % 10 <= 4 && (ly.content.length % 100 < 12 || ly.content.length % 100 > 14) ? " wersy" : " wersów")
            color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
        }
    }

    // ——— Pisz ———
    Flickable {
        id: writeFlick
        visible: ly.mode === "write"
        x: 14; y: head.height
        width: parent.width - 28; height: timing.y - y - 10
        contentHeight: editor.height + 20
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Rectangle {
            width: parent.width; height: Math.max(writeFlick.height, editor.height + 20); radius: 12
            color: Theme.fill
            border.width: editor.activeFocus ? 2 : 0; border.color: Theme.accent
            MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onClicked: editor.forceActiveFocus() }
        }
        TextEdit {
            id: editor
            x: 12; y: 10
            width: parent.width - 24
            wrapMode: TextEdit.Wrap
            selectByMouse: true
            color: Theme.text
            selectionColor: Theme.accentSoft
            selectedTextColor: Theme.text
            font.family: Theme.font; font.pixelSize: 14
            text: Studio.lyrics
            onTextChanged: if (activeFocus || text !== Studio.lyrics) Studio.lyrics = text
            Connections {
                target: Studio
                function onLyricsChanged() { if (!editor.activeFocus && editor.text !== Studio.lyrics) editor.text = Studio.lyrics; }
            }
            // Kursor widoczny przy pisaniu długiego tekstu
            onCursorRectangleChanged: {
                const y = cursorRectangle.y + 10;
                if (y < writeFlick.contentY) writeFlick.contentY = y;
                else if (y + cursorRectangle.height + 20 > writeFlick.contentY + writeFlick.height)
                    writeFlick.contentY = y + cursorRectangle.height + 20 - writeFlick.height;
            }
            Text {
                visible: editor.text === ""
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Wpisz albo wklej tekst — jeden wers w wierszu.\n\nCzęści podpisz w nawiasach, np. [Zwrotka 1], [Refren]. Rymy pokolorują się w widoku Czytaj."
                color: Theme.text2
                font: editor.font
            }
        }
    }

    // ——— Czytaj ———
    ListView {
        id: list
        visible: ly.mode === "read"
        x: 8; y: head.height
        width: parent.width - 16; height: timing.y - y - 10
        clip: true
        model: ly.lines
        boundsBehavior: Flickable.StopAtBounds
        spacing: 2
        // Bieżący wers zawsze na widoku
        Connections {
            target: ly
            function onCurrentChanged() { if (ly.current >= 0 && list.visible) list.positionViewAtIndex(ly.current, ListView.Contain); }
        }
        delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property bool isLine: modelData.kind === "line"
            readonly property bool now: modelData.line === ly.current
            readonly property bool waiting: ly.syncing && isLine && ly.content[ly.syncIndex] && ly.content[ly.syncIndex].line === modelData.line
            width: list.width
            height: modelData.kind === "blank" ? 10 : modelData.kind === "head" ? 28 : Math.max(30, lineText.implicitHeight + 12)
            radius: 8
            color: now ? Theme.accentSoft : waiting ? Qt.rgba(0.96, 0.72, 0.24, 0.22) : rowArea.containsMouse && isLine ? Theme.hover : "transparent"
            Text {
                visible: row.modelData.kind === "head"
                x: 8; anchors.bottom: parent.bottom; anchors.bottomMargin: 4
                text: row.modelData.text.trim().replace(/^[\[(#]\s*|[\])]$|:$/g, "").toUpperCase()
                color: Theme.text2
                font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.6
            }
            // Takt wersu; pogrubiony — ustawiony ręcznie
            Text {
                visible: row.isLine
                x: 6; y: 8; width: 34
                text: "t. " + row.modelData.bar
                color: row.modelData.marked ? Theme.accentText : Theme.text2
                font.family: Theme.font; font.pixelSize: 11; font.weight: row.modelData.marked ? Font.DemiBold : Font.Normal; font.features: { "tnum": 1 }
            }
            LyricText {
                id: lineText
                visible: row.isLine
                x: 44; y: 6; width: parent.width - 52
                line: row.modelData
                font.pixelSize: 14
                font.weight: row.now ? Font.DemiBold : Font.Normal
            }
            MouseArea {
                id: rowArea
                anchors.fill: parent
                enabled: row.isLine
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (e) => {
                    if (e.button === Qt.RightButton) {
                        Studio.markLyric(row.modelData.line, -1);      // znów według taktów
                    } else if (ly.syncing || ((Studio.playing || Studio.recording) && e.modifiers & Qt.ShiftModifier)) {
                        Studio.markLyric(row.modelData.line, Studio.position);
                        if (ly.syncing) ly.syncIndex = row.modelData.index + 1 < ly.content.length ? row.modelData.index + 1 : -1;
                    } else if (!Studio.recording) {
                        Studio.seek(Math.max(0, row.modelData.beat * ly.spb));
                    }
                }
            }
        }
        Text {
            visible: ly.content.length === 0
            x: 8; y: 8; width: parent.width - 16
            wrapMode: Text.WordWrap
            text: "Nie ma jeszcze tekstu. Przejdź do „Pisz” i wpisz zwrotkę."
            color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
        }
    }

    // ——— Czas wersów ———
    Rectangle {
        id: timing
        x: 12; width: parent.width - 24
        y: parent.height - height - 12
        height: timingCol.height + 24; radius: 12
        color: Theme.pane
        border.width: 1; border.color: Theme.line
        Column {
            id: timingCol
            x: 12; y: 12
            width: parent.width - 24
            spacing: 10
            Text { text: "Czas wersów"; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Bold }
            Row {
                spacing: 6
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Od taktu"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                SmallBtn { label: "−"; onClicked: Studio.lyricsStart = Studio.lyricsStart - 1 }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 26; horizontalAlignment: Text.AlignHCenter
                    text: Studio.lyricsStart
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold; font.features: { "tnum": 1 }
                }
                SmallBtn { label: "+"; onClicked: Studio.lyricsStart = Studio.lyricsStart + 1 }
                SmallBtn {
                    label: "z głowicy"
                    hint: "Pierwszy wers w takcie, w którym stoi głowica"
                    onClicked: Studio.lyricsStart = Math.floor(Math.max(0, Studio.position) / (ly.spb * Studio.beatsPerBar)) + 1
                }
            }
            Row {
                spacing: 8
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Wers trwa"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                Segmented {
                    model: [{ label: "1 takt", value: 1 }, { label: "2 takty", value: 2 }]
                    value: Studio.lyricsBars
                    onPicked: (v) => Studio.lyricsBars = v
                }
            }
            HoverButton {
                width: parent.width; height: 34; radius: 10
                baseColor: ly.syncing ? Theme.accent : Theme.fill
                color: ly.syncing ? baseColor : hovered ? Theme.hover : baseColor
                enabled: ly.content.length > 0 && !Studio.recording
                opacity: enabled ? 1 : 0.5
                onClicked: { if (ly.syncing) { ly.syncIndex = -1; Studio.stop(); } else { ly.mode = "read"; ly.startSync(); } }
                Text {
                    anchors.centerIn: parent
                    text: ly.syncing ? "Naciskaj ↓ na początku wersu " + (ly.syncIndex + 1) + " · Zakończ" : "Ustaw wersy w trakcie grania"
                    color: ly.syncing ? "white" : Theme.text
                    font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                }
                Tip { shown: parent.hovered && !ly.syncing; text: "Gra od taktu przed pierwszym wersem; naciskasz ↓ (albo klikasz wers), gdy zaczyna się kolejny" }
            }
            Row {
                spacing: 6
                SmallBtn {
                    label: "Według taktów"
                    hint: "Zapomnij wersy ustawione ręcznie (prawy przycisk na wersie — tylko ten jeden)"
                    enabled: ly.lines.some((l) => l.marked)
                    onClicked: Studio.clearLyricMarks()
                }
                SmallBtn {
                    label: ly.prompter ? "Prompter: wł." : "Prompter: wył."
                    hint: "Duży tekst nad osią czasu w trakcie nagrywania"
                    on: ly.prompter
                    onClicked: ly.prompter = !ly.prompter
                }
            }
        }
    }

    component SmallBtn: HoverButton {
        id: sb
        property string label
        property string hint
        property bool on: false
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        width: Math.max(26, sbText.implicitWidth + 16); height: 26; radius: 8
        baseColor: on ? Theme.accentSoft : Theme.fill
        color: hovered ? Theme.hover : baseColor
        opacity: enabled ? 1 : 0.45
        Text { id: sbText; anchors.centerIn: parent; text: sb.label; color: sb.on ? Theme.accentText : Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
        Tip { shown: sb.hovered && sb.hint !== ""; text: sb.hint }
    }
}
