#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QQuickWindow>
#include <QVariantList>

// Most między QML a systemem: warstwy Wayland, rozmycie KWin, programy, pliki, sesja.
// Udaje też usługę D-Bus „org.kde.plasmashell”, żeby klawisz Super (obsługiwany przez KWin)
// otwierał nasz Start zamiast menu Plasmy.
class Platform : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.PlasmaShell")
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QString dataDir READ dataDir CONSTANT)
    Q_PROPERTY(QString userName READ userName CONSTANT)

public:
    explicit Platform(QObject *parent = nullptr);

    // Katalog z tapetami i innymi zasobami (ASTER_DATA_DIR nadpisuje — przydatne przy pracy nad kodem)
    QString dataDir() const;
    // Imię i nazwisko z konta (albo login, jeśli puste)
    QString userName() const;

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

    // Aplikacja po nazwie pliku .desktop (np. "org.kde.dolphin"): {name, icon, valid}
    Q_INVOKABLE QVariantMap appInfo(const QString &desktopId) const;
    Q_INVOKABLE void launchApp(const QString &desktopId);

    // Ostatnio używane pliki (z ~/.local/share/recently-used.xbel): [{name, url, icon, modified}, ...]
    Q_INVOKABLE QVariantList recentFiles(int count) const;
    Q_INVOKABLE void openUrl(const QString &url);

    Q_INVOKABLE void lockScreen();
    Q_INVOKABLE void shutdownPrompt();
    Q_INVOKABLE void run(const QString &program, const QStringList &args = {});

    // Wywoływane przez KWin po wciśnięciu Super
    Q_SCRIPTABLE void activateLauncherMenu();

Q_SIGNALS:
    void launcherRequested();
};
