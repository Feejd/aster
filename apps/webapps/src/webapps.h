#pragma once

#include <QNetworkAccessManager>
#include <QObject>
#include <QQmlEngine>
#include <QUrl>
#include <QVariantMap>

#include <functional>

// Instalator aplikacji webowych. Ze strony czyta to, co sama o sobie mówi (manifest PWA:
// nazwa, kolory, ikony, zakres adresów; a gdy go nie ma — tytuł, theme-color, apple-touch-icon),
// robi z ikony kafelek w stylu Aster i zapisuje aplikację jako zwykły program w systemie
// (plik .desktop → widać ją w Starcie, w doku, w „Otwórz za pomocą”).
//
// Dane aplikacji: ~/.local/share/aster/webapps/<id>/ (app.json, icon.png, profile/)
// Plik programu:  ~/.local/share/applications/aster-webapp-<id>.desktop
class WebApps : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QVariantList installed READ installed NOTIFY installedChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)

public:
    explicit WebApps(QObject *parent = nullptr);

    static QString dataDir();
    static QString appDir(const QString &id);
    // Dane zainstalowanej aplikacji (pusta mapa, jeśli nie ma takiej)
    static QVariantMap load(const QString &id);

    QVariantList installed() const;
    bool busy() const { return m_busy; }

    // Sprawdza stronę → inspected({url, name, themeColor, backgroundColor, scope, icon, host}) albo failed(tekst)
    Q_INVOKABLE void inspect(const QString &url);
    // Instaluje z danych z inspect() (można zmienić name, category, themeColor) → installedApp(id)
    Q_INVOKABLE void install(const QVariantMap &info);
    Q_INVOKABLE void uninstall(const QString &id);
    Q_INVOKABLE void launch(const QString &id);
    Q_INVOKABLE bool isInstalledUrl(const QString &url) const;
    Q_INVOKABLE QString idForUrl(const QString &url) const;

Q_SIGNALS:
    void installedChanged();
    void busyChanged();
    void inspected(const QVariantMap &info);
    void installedApp(const QString &id);
    void failed(const QString &message);

private:
    using Callback = std::function<void(const QByteArray &data, const QUrl &finalUrl, bool ok, int status)>;
    void fetch(const QUrl &url, Callback done);
    void tryIcons(QStringList candidates, std::function<void(const QImage &, bool maskable)> done);
    void setBusy(bool busy);

    QNetworkAccessManager m_net;
    bool m_busy = false;
};

// Kafelek ikony w stylu Aster (256×256, zaokrąglony kwadrat): ikony pełne (maskable, apple-touch-icon)
// wypełniają kafelek, małe znaki stron stoją na środku jasnego tła.
QImage composeIcon(const QImage &src, bool maskable, const QColor &background);
