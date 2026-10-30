#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QQuickWindow>

// Wygląd okien aplikacji Aster: rozmycie tła przez KWin i obszar przyjmujący kliknięcia
// (cień wokół okna bez ramki nie łapie kliknięć — przechodzą do okien pod spodem).
class WindowEffects : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    // Do testów: ASTER_DARK=1 wymusza ciemny motyw we wszystkich aplikacjach Aster
    Q_PROPERTY(bool forceDark READ forceDark CONSTANT)

public:
    explicit WindowEffects(QObject *parent = nullptr);
    bool forceDark() const { return qEnvironmentVariableIsSet("ASTER_DARK"); }

    Q_INVOKABLE void setBlur(QQuickWindow *window, const QRectF &rect, qreal radius);
    Q_INVOKABLE void setInputRegion(QQuickWindow *window, const QRectF &rect);
};
