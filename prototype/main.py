"""Prototyp powłoki Aster w QML.

Uruchomienie:  python main.py
Zrzut ekranu:  python main.py --shot out.png [--panel start|control] [--dark] [--query tekst]
"""
import argparse
import sys
from pathlib import Path

from PySide6.QtCore import Q_ARG, QMetaObject, QTimer, QUrl
from PySide6.QtGui import QFont, QFontDatabase, QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine, QQmlEngine, QQmlExpression
from PySide6.QtQuick import QQuickItem

HERE = Path(__file__).resolve().parent


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--shot", help="zapisz zrzut okna do pliku i zakończ")
    parser.add_argument("--panel", default="", choices=["", "start", "control", "assistant"])
    parser.add_argument("--dark", action="store_true")
    parser.add_argument("--query", default="", help="tekst wpisany w Start")
    parser.add_argument("--say", action="append", default=[], help="wiadomość do asystenta (można powtórzyć)")
    parser.add_argument("--eval", action="append", default=[], help="wyrażenie QML do wykonania (testy), co 400 ms")
    parser.add_argument("--burst", help="seria zrzutów: prefiks:start_ms:krok_ms:ile (do podglądu animacji)")
    parser.add_argument("--approve", action="store_true", help="zatwierdź ostatnią propozycję asystenta")
    args, qt_args = parser.parse_known_args()

    app = QGuiApplication([sys.argv[0], *qt_args])
    app.setApplicationName("Aster")

    font_id = QFontDatabase.addApplicationFont(str(HERE / "fonts" / "InterVariable.ttf"))
    families = QFontDatabase.applicationFontFamilies(font_id)
    if families:
        font = QFont(families[0])
        font.setPixelSize(13)
        app.setFont(font)

    engine = QQmlApplicationEngine()
    engine.load(QUrl.fromLocalFile(str(HERE / "Main.qml")))
    if not engine.rootObjects():
        return 1
    window = engine.rootObjects()[0]
    window.setProperty("dark", args.dark)
    window.setProperty("panel", args.panel)

    if args.query:
        def type_query():
            start = window.findChild(QQuickItem, "startMenu")
            if start is not None:
                start.setProperty("query", args.query)
        QTimer.singleShot(400, type_query)

    if args.say:
        assistant = window.findChild(QQuickItem, "assistant")

        def say(i=0):
            if i < len(args.say):
                QMetaObject.invokeMethod(assistant, "send", Q_ARG("QVariant", args.say[i]))
                QTimer.singleShot(900, lambda: say(i + 1))
            elif args.approve:
                QMetaObject.invokeMethod(assistant, "approveLast")
        QTimer.singleShot(500, say)

    if args.eval:
        context = QQmlEngine.contextForObject(window)

        def run(i=0):
            if i < len(args.eval):
                result = QQmlExpression(context, window, args.eval[i]).evaluate()
                print(f"[eval] {args.eval[i]} -> {result[0] if isinstance(result, tuple) else result}", flush=True)
                QTimer.singleShot(400, lambda: run(i + 1))
        QTimer.singleShot(600, run)

    if args.burst:
        prefix, start, step, count = args.burst.rsplit(":", 3)

        def grab(i=0):
            window.grabWindow().save(f"{prefix}{i}.png")
            if i + 1 < int(count):
                QTimer.singleShot(int(step), lambda: grab(i + 1))
            else:
                app.quit()
        QTimer.singleShot(int(start), grab)

    if args.shot:
        def shoot():
            window.grabWindow().save(args.shot)
            app.quit()
        QTimer.singleShot(1500 + 400 * len(args.eval) + 900 * len(args.say) + (600 if args.approve else 0), shoot)

    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
