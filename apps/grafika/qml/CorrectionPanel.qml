pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Grafika

// Korekcje tonów i kolorów: te same dla zdjęcia i warstwy korekcyjnej. `apply(patch, done)` zapisuje zmiany.
Column {
    id: cp
    required property Project project
    property var el: ({})
    property var apply
    property bool wholePage: false               // warstwa korekcyjna: także jasność, kontrast, nasycenie i gotowe wyglądy
    spacing: 4
    width: parent ? parent.width : 200

    readonly property var sCurve: [[0, 0], [0.25, 0.18], [0.75, 0.84], [1, 1]]
    function look(p) {
        const clear = { brightness: null, contrast: null, saturation: null, exposure: null, shadows: null, highlights: null,
                        temperature: null, tint: null, hue: null, curves: null };
        apply(Object.assign(clear, p), true);
    }
    function isSet() {
        for (const k of ["exposure", "shadows", "highlights", "temperature", "tint", "hue", "brightness", "contrast", "saturation", "curves"])
            if (el[k]) return true;
        return false;
    }

    Flow {
        visible: cp.wholePage
        width: parent.width
        spacing: 6
        bottomPadding: 6
        Chip { text: "Czarno-białe"; onClicked: cp.look({ saturation: -1 }) }
        Chip { text: "Ciepło"; onClicked: cp.look({ temperature: 0.45, saturation: 0.1 }) }
        Chip { text: "Chłodno"; onClicked: cp.look({ temperature: -0.45 }) }
        Chip { text: "Kino"; onClicked: cp.look({ curves: { rgb: cp.sCurve }, saturation: -0.12, temperature: -0.1 }) }
        Chip { text: "Mocny kontrast"; onClicked: cp.look({ curves: { rgb: cp.sCurve } }) }
    }
    Repeater {
        model: (cp.wholePage ? [{ k: "brightness", label: "Jasność" }, { k: "contrast", label: "Kontrast" }, { k: "saturation", label: "Nasycenie" }] : [])
               .concat([{ k: "exposure", label: "Ekspozycja" }, { k: "shadows", label: "Cienie" }, { k: "highlights", label: "Światła" },
                        { k: "temperature", label: "Temperatura" }, { k: "tint", label: "Zieleń — magenta" }])
        delegate: ValueSlider {
            required property var modelData
            label: modelData.label
            from: -1; to: 1; step: 0.02
            value: cp.el[modelData.k] || 0
            shown: value * 100
            onMoved: (v, done) => { const p = {}; p[modelData.k] = Math.abs(v) < 0.001 ? null : v; cp.apply(p, done); }
        }
    }
    ValueSlider {
        label: "Barwa"
        from: -180; to: 180; step: 1
        value: cp.el.hue || 0
        suffix: "°"
        onMoved: (v, done) => cp.apply({ hue: v === 0 ? null : v }, done)
    }
    Item { width: 1; height: 4 }
    Text { text: "Krzywa"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
    CurveEditor {
        project: cp.project
        curves: cp.el.curves || ({})
        onEdited: (c, done) => cp.apply({ curves: c }, done)
    }
    Btn {
        visible: cp.isSet()
        text: "Wyzeruj"
        onClicked: cp.look({})
    }
}
