pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtCore
import Aster.Ui
import Aster.Calculator

// Kalkulator Aster (zamiast KCalc): standardowy i naukowy, z historią. Wpisane działanie widać w całości,
// pod nim — wynik na żywo; „=” przenosi wynik na duży wyświetlacz. Klawiatura działa jak w Windows
// (cyfry, + − * /, Enter, Backspace, Esc, %), przecinek i kropka to przecinek dziesiętny.
Window {
    id: win
    width: (science ? 640 : 380) + (historyOpen ? 300 : 0) + 2 * m
    height: 600 + 2 * m
    minimumWidth: 320 + 2 * m
    minimumHeight: 480 + 2 * m
    visible: true
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    title: "Kalkulator"

    readonly property bool maxed: visibility === Window.Maximized || visibility === Window.FullScreen
    readonly property int m: maxed ? 0 : 26
    readonly property real r: visibility === Window.FullScreen ? 0 : 12

    Settings {
        id: prefs
        category: "calculator"
        property alias science: win.science
        property alias degrees: win.degrees
    }
    property bool science: false
    property bool degrees: true
    property bool inverse: false
    property bool historyOpen: false
    readonly property bool wide: frame.width >= (science ? 640 : 380) + 280

    // ——— Stan ———
    property string expr: ""                 // wpisywane działanie (bez odstępów tysięcy)
    property string shown: ""                // działanie nad wynikiem po „=”
    property bool evaluated: false
    property string error: ""
    readonly property var preview: { expr; degrees; return /[+−×÷^%!²³√a-zπ(]/.test(expr.replace(/^−/, "")) ? Calc.evaluate(expr, degrees) : ({ ok: false }); }

    readonly property string binaryOps: " + | − | × | ÷ "
    function endsWithOp() { return / [+−×÷] $/.test(expr) || /\^$/.test(expr); }
    function lastNumber() { const mm = expr.match(/[0-9,]+$/); return mm ? mm[0] : ""; }
    function pretty(s) {
        // Odstępy tysięcy w każdej liczbie
        return s.replace(/[0-9]+(,[0-9]*)?/g, n => Calc.group(n));
    }
    function startFresh(keepResult) {
        if (!evaluated) return;
        evaluated = false;
        shown = "";
        if (!keepResult) expr = "";
    }

    function digit(d) {
        error = "";
        startFresh(false);
        if (lastNumber() === "0") expr = expr.slice(0, -1);
        if (/[)!%²³πe]$/.test(expr)) expr += " × ";
        expr += d;
    }
    function comma() {
        error = "";
        startFresh(false);
        const n = lastNumber();
        if (n.indexOf(",") >= 0) return;
        expr += n === "" ? "0," : ",";
    }
    function op(o) {
        error = "";
        startFresh(true);
        if (expr === "" || expr === "−") {
            if (o === "−") expr = "−";
            else if (expr === "") expr = "0 " + o + " ";
            return;
        }
        if (endsWithOp()) expr = expr.replace(/ [+−×÷] $|\^$/, "");
        if (/[(,]$/.test(expr) && o !== "−") return;
        expr += o === "^" ? "^" : " " + o + " ";
    }
    function append(t) {
        error = "";
        startFresh(t === "%" || t === "²" || t === "³" || t === "!" || t === ")");
        if (/^[a-z√(]/.test(t) || t === "π" || t === "e") {
            if (/[0-9)!%²³πe]$/.test(expr)) expr += " × ";
        }
        expr += t;
    }
    function equals() {
        if (evaluated || expr === "") return;
        const res = Calc.evaluate(expr, degrees);
        if (!res.ok) { error = res.error || "Nieprawidłowe wyrażenie"; return; }
        const full = pretty(expr) + closingParens();
        Calc.addHistory(full, res.text);
        shown = full + " =";
        expr = res.text.replace(/ /g, "");
        evaluated = true;
        error = "";
    }
    function closingParens() {
        const open = (expr.match(/\(/g) || []).length - (expr.match(/\)/g) || []).length;
        return ")".repeat(Math.max(0, open));
    }
    function backspace() {
        error = "";
        if (evaluated) { shown = ""; evaluated = false; return; }
        if (/ [+−×÷] $/.test(expr)) expr = expr.slice(0, -3);
        else if (/(asin|acos|atan|sin|cos|tan|abs|ln|log)\($/.test(expr)) expr = expr.replace(/(asin|acos|atan|sin|cos|tan|abs|ln|log)\($/, "");
        else expr = expr.slice(0, -1);
    }
    function clearAll() { expr = ""; shown = ""; evaluated = false; error = ""; }
    function clearEntry() {
        error = "";
        if (evaluated) { clearAll(); return; }
        expr = expr.replace(/−?[0-9,]+$/, "");
    }
    function negate() {
        error = "";
        startFresh(true);
        const mm = expr.match(/(^|[ (^])(−?)([0-9,]+)$/);
        if (!mm) { if (expr === "") expr = "−"; return; }
        const start = expr.length - mm[2].length - mm[3].length;
        expr = expr.slice(0, start) + (mm[2] ? "" : "−") + mm[3];
    }
    function wrapLast(prefix, suffix) {
        // Ostatnia liczba (albo wynik) w funkcji: √(9), 1÷(4), sqr…
        error = "";
        startFresh(true);
        const mm = expr.match(/−?[0-9,]+$|\([^()]*\)$/);
        if (!mm) { expr += prefix; return; }
        expr = expr.slice(0, expr.length - mm[0].length) + prefix + mm[0] + suffix;
    }
    function copy() { Calc.toClipboard(evaluated || !preview.ok ? pretty(expr) : preview.text); toast("Skopiowano"); }
    function paste() {
        const t = Calc.fromClipboard();
        if (!t) return;
        startFresh(false);
        expr += t.replace(/([+−×÷])/g, " $1 ").replace(/  +/g, " ");
    }
    function useHistory(h) {
        expr = h.result.replace(/ /g, "");
        shown = h.expr + " =";
        evaluated = true;
        error = "";
        if (!wide) historyOpen = false;
    }

    function toast(text) { toastBox.text = text; toastBox.shown = true; toastTimer.restart(); }

    // Klawiatura
    function typeKeys(s) {
        for (const ch of s) {
            if (/[0-9]/.test(ch)) digit(ch);
            else if (ch === "," || ch === ".") comma();
            else if (ch === "+") op("+");
            else if (ch === "-" || ch === "−") op("−");
            else if (ch === "*" || ch === "×") op("×");
            else if (ch === "/" || ch === "÷") op("÷");
            else if (ch === "^") op("^");
            else if (ch === "=") equals();
            else if (ch === "%" || ch === "!" || ch === "(" || ch === ")" || ch === "²" || ch === "π") append(ch);
            else if (ch === "s") append("sin(");
            else if (ch === "r") append("√(");
            else if (ch === "n") negate();
            else if (ch === "<") backspace();
        }
    }
    // ASTER_TEST=1: wpisanie działań klawiszami i porównanie wyników
    function selfTest() {
        const cases = [["0.1+0.2=", "0,3"], ["2+3*4=", "14"], ["200+10%=", "220"], ["200*10%=", "20"], ["1/3*3=", "1"],
                       ["7/0=", "!"], ["12345678*9=", "111 111 102"], ["2^10=", "1024"], ["5!=", "120"], ["s30)=", "0,5"],
                       ["r16)=", "4"], ["(2+3)*4=", "20"], ["5n*3=", "−15"], ["1,5+1,25=", "2,75"], ["99999999*99999999=", "9 999 999 800 000 001"], ["1/3=", "0,33333333333333333"], ["2^100=", "1,2676506e+30"], ["s180)=", "0"], ["99999999999999999*10=", "1e+18"],
                       ["2(3+4=", "14"], ["0.1*3=", "0,3"], ["10-2-3=", "5"], ["2^3^2=", "512"], ["123<4=", "124"]];
        let fail = 0;
        for (const [keys, want] of cases) {
            clearAll();
            typeKeys(keys);
            const got = error ? "!" : Calc.evaluate(expr, degrees).text;
            const ok = got.replace(/ /g, " ") === want;
            if (!ok) fail++;
            console.log((ok ? "OK   " : "BŁĄD ") + keys + " → " + got.replace(/ /g, " ") + (ok ? "" : "  (oczekiwano " + want + ")"));
        }
        console.log(fail ? "Błędów: " + fail : "Wszystkie testy przeszły");
    }
    function testOpen(what) {
        if (what === "science") science = true;
        else if (what === "history") historyOpen = true;
    }

    Item {
        focus: true
        Keys.onPressed: (e) => {
            const t = e.text;
            if (e.modifiers & Qt.ControlModifier) {
                if (e.key === Qt.Key_C) win.copy();
                else if (e.key === Qt.Key_V) win.paste();
                else if (e.key === Qt.Key_H) win.historyOpen = !win.historyOpen;
                else return;
            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || t === "=") win.equals();
            else if (e.key === Qt.Key_Backspace) win.backspace();
            else if (e.key === Qt.Key_Escape) win.clearAll();
            else if (e.key === Qt.Key_Delete) win.clearEntry();
            else if (e.key === Qt.Key_F9) win.negate();
            else if (t && /[0-9.,+\-*/^%!()]/.test(t)) win.typeKeys(t);
            else return;
            e.accepted = true;
        }
    }

    // ——— Okno ———
    function updateEffects() {
        WindowEffects.setBlur(win, Qt.rect(m, m, frame.width, frame.height), r);
        WindowEffects.setInputRegion(win, Qt.rect(Math.max(0, m - 6), Math.max(0, m - 6), frame.width + (maxed ? 0 : 12), frame.height + (maxed ? 0 : 12)));
    }
    Component.onCompleted: effectsTimer.restart()
    onWidthChanged: effectsTimer.restart()
    onHeightChanged: effectsTimer.restart()
    onMaxedChanged: effectsTimer.restart()
    Timer { id: effectsTimer; interval: 16; onTriggered: win.updateEffects() }

    WindowShadow { window: win; frame: frame; radius: win.r; visible: !win.maxed }
    ResizeHandles { window: win; frame: frame; margin: win.m }

    Rectangle {
        id: frame
        x: win.m; y: win.m
        width: win.width - 2 * win.m
        height: win.height - 2 * win.m
        radius: win.r
        color: Theme.windowGlass
        border.width: win.maxed ? 0 : 1
        border.color: Theme.edge
        WindowSheen { window: win; radius: win.r }
        clip: true

        // ——— Pasek u góry ———
        Item {
            id: top
            width: parent.width; height: 52
            DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
            Rectangle {
                x: 14; anchors.verticalCenter: parent.verticalCenter
                width: modeRow.width + 6; height: 30; radius: 10
                color: Theme.fill
                Row {
                    id: modeRow
                    x: 3; anchors.verticalCenter: parent.verticalCenter
                    Repeater {
                        model: [["Standardowy", false], ["Naukowy", true]]
                        delegate: Rectangle {
                            id: seg
                            required property var modelData
                            readonly property bool on: win.science === modelData[1]
                            width: segText.implicitWidth + 22; height: 24; radius: 8
                            color: on ? Theme.surface : "transparent"
                            Text { id: segText; anchors.centerIn: parent; text: seg.modelData[0]; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: seg.on ? Font.Medium : Font.Normal }
                            MouseArea { anchors.fill: parent; onClicked: win.science = seg.modelData[1] }
                        }
                    }
                }
            }
            ToolBtn {
                anchors.right: winButtons.left; anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                icon: "clock"
                onClicked: win.historyOpen = !win.historyOpen
            }
            WindowButtons {
                id: winButtons
                window: win
                anchors.right: parent.right; anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // ——— Wyświetlacz i przyciski ———
        Item {
            id: calc
            y: top.height
            width: parent.width - (win.historyOpen && win.wide ? history.width : 0)
            height: parent.height - y

            Column {
                id: display
                x: 22; width: parent.width - 44
                spacing: 2
                // Działanie po „=” albo wynik na żywo podczas wpisywania
                Text {
                    width: parent.width; height: 26
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideLeft
                    text: win.evaluated ? win.shown : ""
                    color: Theme.text2
                    font.family: Theme.font; font.pixelSize: 16
                    font.features: { "tnum": 1 }
                }
                Text {
                    id: big
                    width: parent.width; height: 72
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: 20
                    elide: Text.ElideLeft
                    text: win.expr === "" ? "0" : win.pretty(win.expr) + (win.evaluated ? "" : "")
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: win.evaluated ? 54 : 46; font.weight: win.evaluated ? Font.DemiBold : Font.Medium
                    font.features: { "tnum": 1 }
                    font.letterSpacing: -0.5
                    Behavior on font.pixelSize { NumberAnimation { duration: 140 } }
                }
                Text {
                    width: parent.width; height: 24
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideLeft
                    text: win.error ? win.error : (!win.evaluated && win.preview.ok ? "= " + win.preview.text : "")
                    color: win.error ? Theme.danger : Theme.text2
                    font.family: Theme.font; font.pixelSize: 18
                    font.features: { "tnum": 1 }
                }
            }

            // Rzędy przycisków; „=” w trybie naukowym zajmuje dwa pola
            Column {
                id: pad
                x: 12; y: display.y + display.height + 10
                width: parent.width - 24; height: parent.height - y - 12
                spacing: 6
                readonly property var rows: win.science ? [
                    [[win.degrees ? "DEG" : "RAD", "mode", "fn"], [win.inverse ? "INV" : "inv", "inv", "fn"], ["(", "(", "fn"], [")", ")", "fn"], ["CE", "ce", "op"], ["C", "c", "op"], ["⌫", "bs", "op"]],
                    [[win.inverse ? "sin⁻¹" : "sin", win.inverse ? "asin(" : "sin(", "fn"], [win.inverse ? "cos⁻¹" : "cos", win.inverse ? "acos(" : "cos(", "fn"], [win.inverse ? "tan⁻¹" : "tan", win.inverse ? "atan(" : "tan(", "fn"], ["7", "7", "num"], ["8", "8", "num"], ["9", "9", "num"], ["÷", "÷", "op"]],
                    [["x²", "²", "fn"], ["xʸ", "^", "fn"], ["√x", "sqrt", "fn"], ["4", "4", "num"], ["5", "5", "num"], ["6", "6", "num"], ["×", "×", "op"]],
                    [["ln", "ln(", "fn"], ["log", "log(", "fn"], ["n!", "!", "fn"], ["1", "1", "num"], ["2", "2", "num"], ["3", "3", "num"], ["−", "−", "op"]],
                    [["π", "π", "fn"], ["e", "e", "fn"], ["%", "%", "fn"], ["±", "neg", "num"], ["0", "0", "num"], [",", ",", "num"], ["+", "+", "op"]],
                    [["|x|", "abs(", "fn"], ["¹⁄ₓ", "inv1", "fn"], ["x³", "³", "fn"], ["10ˣ", "10^", "fn"], ["eˣ", "exp(", "fn"], ["=", "=", "eq", 2]]
                ] : [
                    [["%", "%", "op"], ["CE", "ce", "op"], ["C", "c", "op"], ["⌫", "bs", "op"]],
                    [["¹⁄ₓ", "inv1", "op"], ["x²", "²", "op"], ["²√x", "sqrt", "op"], ["÷", "÷", "op"]],
                    [["7", "7", "num"], ["8", "8", "num"], ["9", "9", "num"], ["×", "×", "op"]],
                    [["4", "4", "num"], ["5", "5", "num"], ["6", "6", "num"], ["−", "−", "op"]],
                    [["1", "1", "num"], ["2", "2", "num"], ["3", "3", "num"], ["+", "+", "op"]],
                    [["±", "neg", "num"], ["0", "0", "num"], [",", ",", "num"], ["=", "=", "eq"]]
                ]
                readonly property int columns: win.science ? 7 : 4
                readonly property real cw: (width - (columns - 1) * spacing) / columns
                readonly property real ch: (height - (rows.length - 1) * spacing) / rows.length
                Repeater {
                    model: pad.rows
                    delegate: Row {
                        id: keyRow
                        required property var modelData
                        spacing: pad.spacing
                        Repeater {
                            model: keyRow.modelData
                            delegate: Key {}
                        }
                    }
                }
            }
        }

        // ——— Historia ———
        Rectangle {
            id: history
            visible: win.historyOpen
            anchors.right: parent.right
            y: top.height
            width: win.wide ? 300 : parent.width
            height: parent.height - y
            color: win.wide ? "transparent" : Theme.paneGlass
            bottomLeftRadius: win.r; bottomRightRadius: win.r
            Rectangle { visible: win.wide; width: 1; height: parent.height; color: Theme.line }
            Text { x: 22; y: 6; text: "Historia"; color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.Bold }
            ToolBtn {
                anchors.right: parent.right; anchors.rightMargin: 12; y: 0
                visible: Calc.history.length > 0
                icon: "trash"
                onClicked: Calc.clearHistory()
            }
            Text {
                visible: Calc.history.length === 0
                x: 22; y: 44; width: parent.width - 44
                wrapMode: Text.Wrap
                text: "Tu pojawią się policzone działania. Kliknij je, żeby wrócić do wyniku."
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
            }
            ListView {
                y: 40
                width: parent.width; height: parent.height - y - 8
                clip: true
                model: Calc.history
                boundsBehavior: Flickable.StopAtBounds
                delegate: HoverButton {
                    id: he
                    required property var modelData
                    x: 10; width: ListView.view.width - 20
                    height: heCol.implicitHeight + 16; radius: 10
                    onClicked: win.useHistory(he.modelData)
                    Column {
                        id: heCol
                        x: 12; y: 8; width: parent.width - 24
                        Text { width: parent.width; horizontalAlignment: Text.AlignRight; wrapMode: Text.WrapAnywhere; text: he.modelData.expr + " ="; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; font.features: { "tnum": 1 } }
                        Text { width: parent.width; horizontalAlignment: Text.AlignRight; elide: Text.ElideLeft; text: he.modelData.result; color: Theme.text; font.family: Theme.font; font.pixelSize: 22; font.weight: Font.DemiBold; font.features: { "tnum": 1 } }
                    }
                }
            }
        }

        Rectangle {
            id: toastBox
            property bool shown: false
            property alias text: toastText.text
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - (shown ? height + 18 : 0)
            opacity: shown ? 1 : 0
            z: 300
            width: toastText.implicitWidth + 32; height: 34; radius: 17
            color: Theme.dark ? "#ECEEF3" : "#1E2027"
            Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutQuint } }
            Behavior on opacity { NumberAnimation { duration: 160 } }
            Text { id: toastText; anchors.centerIn: parent; color: Theme.dark ? "#16181D" : "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
            Timer { id: toastTimer; interval: 1500; onTriggered: toastBox.shown = false }
        }
    }

    // Przycisk: cyfry jaśniej, działania na szkle, „=” w kolorze akcentu
    component Key: HoverButton {
        id: key
        required property var modelData
        readonly property string kind: modelData[2]
        readonly property int span: modelData[3] || 1
        width: pad.cw * span + pad.spacing * (span - 1); height: pad.ch
        radius: 12
        baseColor: kind === "eq" ? Theme.accent : kind === "num" ? (Theme.dark ? Qt.rgba(1, 1, 1, 0.11) : Qt.rgba(1, 1, 1, 0.92))
                 : (Theme.dark ? Qt.rgba(1, 1, 1, 0.055) : Qt.rgba(1, 1, 1, 0.5))
        color: hovered ? (kind === "eq" ? Qt.darker(Theme.accent, 1.1) : Theme.dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 1)) : baseColor
        border.width: Theme.dark ? 0 : 1
        border.color: Theme.edge
        onClicked: {
            const a = key.modelData[1];
            if (/^[0-9]$/.test(a)) win.digit(a);
            else if (a === ",") win.comma();
            else if (a === "+" || a === "−" || a === "×" || a === "÷" || a === "^") win.op(a === "−" ? "−" : a === "×" ? "×" : a === "÷" ? "÷" : a);
            else if (a === "=") win.equals();
            else if (a === "c") win.clearAll();
            else if (a === "ce") win.clearEntry();
            else if (a === "bs") win.backspace();
            else if (a === "neg") win.negate();
            else if (a === "sqrt") win.wrapLast("√(", ")");
            else if (a === "inv1") win.wrapLast("1÷(", ")");
            else if (a === "mode") win.degrees = !win.degrees;
            else if (a === "inv") win.inverse = !win.inverse;
            else if (a === "10^") win.append("10^(");
            else win.append(a);
        }
        Text {
            anchors.centerIn: parent
            text: key.modelData[0]
            color: key.kind === "eq" ? "white" : (key.modelData[1] === "inv" && win.inverse) ? Theme.accentText : Theme.text
            font.family: Theme.font
            // Znaki działań (÷ × − +) są w czcionce drobne — większe, żeby były czytelne
            font.pixelSize: key.kind === "num" ? 22 : key.kind === "eq" || /^[÷×−+]$/.test(key.modelData[0]) ? 25 : (win.science ? 15 : 18)
            font.weight: key.kind === "num" ? Font.Medium : Font.Normal
        }
    }
}
