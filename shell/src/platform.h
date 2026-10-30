#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QQuickWindow>
#include <QVariantList>

// Most między QML a systemem: warstwy Wayland, rozmycie KWin, uruchamianie programów.
class Platform : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QString dataDir READ dataDir CONSTANT)

public:
    explicit Platform(QObject *parent = nullptr);

    // Katalog z tapetami i innymi zasobami (ASTER_DATA_DIR nadpisuje — przydatne przy pracy nad kodem)
    QString dataDir() const;

    // Zamienia okno w powierzchnię warstwy. Wywołać przed pokazaniem okna.
    // layer: background | bottom | top | overlay
    // anchors: suma krawędzi — 1 góra, 2 dół, 4 lewo, 8 prawo
    // keyboard: none | exclusive | ondemand
    Q_INVOKABLE void makeLayer(QQuickWindow *window, const QString &layer, int anchors,
                               int exclusiveZone, const QString &keyboard, const QString &scope);

    // Rozmycie tła pod podanymi prostokątami: [{x, y, w, h, r}, ...] (r = promień zaokrąglenia)
    Q_INVOKABLE void setBlur(QQuickWindow *window, const QVariantList &rects);

    // Obszar przyjmujący kliknięcia (reszta okna jest „przezroczysta” dla myszy). Format jak w setBlur().
    Q_INVOKABLE void setInputRegion(QQuickWindow *window, const QVariantList &rects);

    Q_INVOKABLE void run(const QString &program, const QStringList &args = {});
};
