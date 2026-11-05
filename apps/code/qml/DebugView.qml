pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Code

// Debugowanie w dolnym panelu: po lewej stos wywołań i zmienne (rozwijane), po prawej konsola debugera
// z wyjściem programu i polem wyrażeń (np. „x * 2”, „p tab[3]”).
Item {
    id: dv
    property var kids: ({})          // ref → elementy rozwiniętej zmiennej
    property var open: ({})              // ref → rozwinięta
    signal openFrame(int index)

    Connections {
        target: Debugger
        function onStopChanged() { dv.kids = {}; dv.open = {}; }
        function onChildrenReady(ref, items) {
            const c = Object.assign({}, dv.kids);
            c[ref] = items;
            dv.kids = c;
        }
    }
    function toggle(ref) {
        const o = Object.assign({}, open);
        if (o[ref]) delete o[ref];
        else { o[ref] = true; if (!kids[ref]) Debugger.expand(ref); }
        open = o;
    }
    readonly property var varRows: {
        const out = [];
        const walk = (items, depth) => {
            for (const it of items) {
                out.push({ kind: "var", depth: depth, name: it.name, value: it.value, type: it.type, ref: it.ref, opened: !!dv.open[it.ref] });
                if (it.ref > 0 && dv.open[it.ref]) walk(dv.kids[it.ref] || [{ name: "…", value: "", type: "", ref: 0 }], depth + 1);
                if (out.length > 2000) return;
            }
        };
        for (const s of Debugger.scopes) {
            const opened = s.expensive ? !!dv.open[s.ref] : !dv.open[-s.ref];
            out.push({ kind: "scope", name: s.name, ref: s.ref, expensive: s.expensive, opened: opened });
            if (opened) walk(s.expensive ? (dv.kids[s.ref] || []) : s.items, 1);
        }
        return out;
    }

    // ——— Lewa strona: stos i zmienne ———
    Item {
        id: left
        width: Math.min(460, parent.width * 0.45); height: parent.height
        Text {
            id: stackTitle
            x: 16; y: 6
            text: "STOS WYWOŁAŃ" + (Debugger.stopReason && Debugger.state === "stopped" ? "  ·  " + Debugger.stopReason : "")
            color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.4
        }
        ListView {
            id: stack
            y: stackTitle.y + stackTitle.height + 4
            width: parent.width; height: Math.min(contentHeight, parent.height * 0.32)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: Debugger.frames
            delegate: Rectangle {
                id: fr
                required property var modelData
                required property int index
                width: ListView.view.width - 12; x: 6; height: 24; radius: 6
                color: index === Debugger.currentFrame ? Theme.accentSoft : frArea.containsMouse ? Theme.hover : "transparent"
                opacity: fr.modelData.path ? 1 : 0.55
                Text {
                    id: fname
                    x: 10; anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, parent.width - 130)
                    elide: Text.ElideRight
                    text: fr.modelData.name
                    color: Theme.text; font.family: "JetBrains Mono"; font.pixelSize: 12
                }
                Text {
                    anchors.left: fname.right; anchors.leftMargin: 8
                    anchors.right: parent.right; anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight; elide: Text.ElideLeft
                    text: fr.modelData.file ? fr.modelData.file + ":" + (fr.modelData.line + 1) : "bez źródła"
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
                }
                MouseArea { id: frArea; anchors.fill: parent; hoverEnabled: true; onClicked: dv.openFrame(fr.index) }
            }
        }
        Rectangle { id: sep; y: stack.y + stack.height + 6; x: 12; width: parent.width - 24; height: 1; color: Theme.line; visible: Debugger.frames.length > 0 }
        ListView {
            y: sep.y + 6
            width: parent.width; height: parent.height - y
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: dv.varRows
            delegate: Item {
                id: vr
                required property var modelData
                width: ListView.view.width; height: 22
                Rectangle { anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6; radius: 5; color: vrArea.containsMouse ? Theme.hover : "transparent" }
                Icon {
                    visible: vr.modelData.kind === "scope" || vr.modelData.ref > 0
                    x: 10 + (vr.modelData.depth || 0) * 14; anchors.verticalCenter: parent.verticalCenter
                    d: vr.modelData.opened ? Icons.chevronDown : Icons.chevronRight; size: 11; stroke: 2; color: Theme.text2
                }
                Text {
                    id: vname
                    x: 26 + (vr.modelData.depth || 0) * 14; anchors.verticalCenter: parent.verticalCenter
                    text: vr.modelData.name + (vr.modelData.kind === "var" ? ":" : "")
                    color: vr.modelData.kind === "scope" ? Theme.text2 : (Theme.dark ? "#C79BFF" : "#8E3FD1")
                    font.family: vr.modelData.kind === "scope" ? Theme.font : "JetBrains Mono"
                    font.pixelSize: vr.modelData.kind === "scope" ? 11 : 12
                    font.weight: vr.modelData.kind === "scope" ? Font.DemiBold : Font.Normal
                }
                Text {
                    visible: vr.modelData.kind === "var"
                    anchors.left: vname.right; anchors.leftMargin: 6
                    anchors.right: parent.right; anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: vr.modelData.value || ""
                    color: Theme.text; font.family: "JetBrains Mono"; font.pixelSize: 12
                }
                MouseArea {
                    id: vrArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (vr.modelData.kind === "scope") dv.toggle(vr.modelData.expensive ? vr.modelData.ref : -vr.modelData.ref);
                        else if (vr.modelData.ref > 0) dv.toggle(vr.modelData.ref);
                    }
                    onDoubleClicked: if (vr.modelData.kind === "var") Project.copyText(vr.modelData.value)
                }
            }
        }
        Text {
            visible: Debugger.state !== "stopped"
            anchors.centerIn: parent
            width: parent.width - 40; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            text: Debugger.state === "running" ? "Program działa — zatrzyma się na punkcie przerwania (F6 — wstrzymaj)"
                : Debugger.state === "starting" ? "Uruchamiam debuger…"
                : "F9 albo klik obok numeru wiersza — punkt przerwania\nF5 — zacznij debugowanie"
            color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.2
        }
    }
    Rectangle { x: left.width; width: 1; height: parent.height; color: Theme.line }

    // ——— Prawa strona: konsola ———
    Item {
        x: left.width + 1; width: parent.width - x; height: parent.height
        ListView {
            id: con
            x: 12; y: 6
            width: parent.width - 20; height: parent.height - y - input.height - 10
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: Debugger.console
            onCountChanged: Qt.callLater(con.positionViewAtEnd)
            delegate: Text {
                required property string modelData
                readonly property string cat: modelData.split("\u001f")[0]
                width: ListView.view.width
                wrapMode: Text.WrapAnywhere
                text: modelData.slice(cat.length + 1) || " "
                color: cat === "stderr" ? Theme.danger : cat === "info" ? Theme.accentText : cat === "input" ? Theme.text2
                     : cat === "result" ? (Theme.dark ? "#7EE0A0" : "#116329") : Theme.text
                font.family: "JetBrains Mono"; font.pixelSize: 12
                font.weight: cat === "info" ? Font.DemiBold : Font.Normal
            }
        }
        Rectangle {
            id: input
            x: 10; anchors.bottom: parent.bottom; anchors.bottomMargin: 8
            width: parent.width - 20; height: 30; radius: 8
            color: Theme.fill
            border.width: expr.activeFocus ? 1.5 : 0; border.color: Theme.accent
            opacity: Debugger.state ? 1 : 0.5
            Text { x: 10; anchors.verticalCenter: parent.verticalCenter; text: "›"; color: Theme.accentText; font.family: "JetBrains Mono"; font.pixelSize: 14 }
            TextInput {
                id: expr
                x: 26; width: parent.width - 34
                anchors.verticalCenter: parent.verticalCenter
                enabled: !!Debugger.state
                color: Theme.text; selectionColor: Theme.accentSoft; selectedTextColor: Theme.text
                font.family: "JetBrains Mono"; font.pixelSize: 12
                clip: true
                property var history: []
                property int hpos: -1
                onAccepted: { if (!text.trim()) return; history = [text].concat(history.filter(h => h !== text)).slice(0, 30); hpos = -1; Debugger.evaluate(text); text = ""; }
                Keys.onUpPressed: if (history.length) { hpos = Math.min(history.length - 1, hpos + 1); text = history[hpos]; }
                Keys.onDownPressed: { hpos = Math.max(-1, hpos - 1); text = hpos >= 0 ? history[hpos] : ""; }
                Text { anchors.verticalCenter: parent.verticalCenter; visible: !expr.text; text: Debugger.state ? "Wyrażenie, np. suma * 2  (:polecenie — dla debugera, np. :info frame)" : "Konsola debugera"; color: Theme.text2; font: expr.font }
            }
        }
    }
}
