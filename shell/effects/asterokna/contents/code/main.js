// Okna Aster: krótkie, spójne otwieranie i zamykanie. Zastępuje efekt „scale” z KDE.
// Programy Aster same wyskakują sprężyście (common/WindowSheen.qml), więc przy otwieraniu ich nie ruszamy.
"use strict";

const OpenMs = 240;
const CloseMs = 150;

class AsterOkna {
    constructor() {
        effects.windowAdded.connect(this.added.bind(this));
        effects.windowClosed.connect(this.closed.bind(this));
    }

    static animated(w) {
        if (w.lockScreen || w.outline || w.popupWindow || !w.managed) return false;
        if (w.windowClass.startsWith("ksmserver") || w.windowClass.startsWith("ksplash")) return false;
        return w.hasDecoration || w.normalWindow || w.dialog;
    }

    static native(w) {
        return w.windowClass.indexOf("org.aster.") !== -1 || w.windowClass.indexOf("aster-") === 0;
    }

    added(w) {
        if (effects.hasActiveFullScreenEffect || !AsterOkna.animated(w) || AsterOkna.native(w) || !w.visible) return;
        if (effect.isGrabbed(w, Effect.WindowAddedGrabRole)) return;
        w.asterIn = animate({
            window: w,
            curve: QEasingCurve.OutBack,
            duration: animationTime(OpenMs),
            animations: [{ type: Effect.Scale, from: 0.94 }]
        });
        animate({
            window: w,
            curve: QEasingCurve.OutQuad,
            duration: animationTime(OpenMs * 0.6),
            animations: [{ type: Effect.Opacity, from: 0 }]
        });
    }

    closed(w) {
        if (effects.hasActiveFullScreenEffect || !AsterOkna.animated(w) || !w.visible || w.skipsCloseAnimation) return;
        if (effect.isGrabbed(w, Effect.WindowClosedGrabRole)) return;
        if (w.asterIn) { cancel(w.asterIn); delete w.asterIn; }
        animate({
            window: w,
            curve: QEasingCurve.InQuad,
            duration: animationTime(CloseMs),
            animations: [{ type: Effect.Scale, to: 0.96 }, { type: Effect.Opacity, to: 0 }]
        });
    }
}

new AsterOkna();
