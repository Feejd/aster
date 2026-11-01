#pragma once

#include <QHash>
#include <QList>
#include <QLocalServer>
#include <QObject>
#include <QPointer>
#include <QQmlEngine>
#include <QTimer>
#include <QVariantList>

class QQuickWebEngineProfile;
class QQuickWebEngineDownloadRequest;
class QQuickWindow;
class QWebEngineNotification;
class DownloadItem;
class TrackerBlocker;

// Serce przeglądarki — jedno na cały program, wspólne dla wszystkich okien:
//  • profile silnika: zwykły (ciasteczka, pamięć podręczna i uprawnienia zostają) i prywatny (nic nie zapisuje),
//  • historia, ulubione, powiększenie stron, ustawienia (wyszukiwarka, przywracanie kart, blokowanie śledzenia),
//  • pobrane pliki, powiadomienia stron jako systemowe,
//  • okna: jedna kopia programu (kolejne uruchomienia przekazują jej adresy), zapis i przywracanie sesji.
class Browser : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QObject *profile READ profile CONSTANT)
    Q_PROPERTY(QObject *privateProfile READ privateProfile CONSTANT)
    Q_PROPERTY(QVariantList bookmarks READ bookmarks NOTIFY bookmarksChanged)
    Q_PROPERTY(int historyRevision READ historyRevision NOTIFY historyChanged)
    Q_PROPERTY(QVariantList downloads READ downloads NOTIFY downloadsChanged)
    Q_PROPERTY(int activeDownloads READ activeDownloads NOTIFY downloadsChanged)
    Q_PROPERTY(QVariantList searchEngines READ searchEngines CONSTANT)
    Q_PROPERTY(QString searchEngine READ searchEngine WRITE setSearchEngine NOTIFY settingsChanged)
    Q_PROPERTY(QString searchName READ searchName NOTIFY settingsChanged)
    Q_PROPERTY(bool restoreSession READ restoreSession WRITE setRestoreSession NOTIFY settingsChanged)
    Q_PROPERTY(bool blockTrackers READ blockTrackers WRITE setBlockTrackers NOTIFY settingsChanged)
    Q_PROPERTY(bool forceDark READ forceDark WRITE setForceDark NOTIFY settingsChanged)
    Q_PROPERTY(bool showFavoritesBar READ showFavoritesBar WRITE setShowFavoritesBar NOTIFY settingsChanged)
    Q_PROPERTY(QString downloadDir READ downloadDir CONSTANT)
    Q_PROPERTY(QString version READ version CONSTANT)
    Q_PROPERTY(QString engineVersion READ engineVersion CONSTANT)
    Q_PROPERTY(bool isDefault READ isDefault NOTIFY settingsChanged)

public:
    explicit Browser(QQmlEngine *engine, QObject *parent = nullptr);
    ~Browser() override;
    static Browser *instance() { return s_instance; }
    static Browser *create(QQmlEngine *, QJSEngine *);

    // Jedna kopia programu: true, gdy inna już działa (dostała adresy — to uruchomienie można zakończyć).
    // Sprawdzane przed utworzeniem Browser — drugi proces nie dotyka nawet profilu silnika.
    static bool forwardToRunning(const QStringList &urls, bool privateMode);
    void listen();
    // Pierwsze okna: przywrócona sesja albo nowa karta, do tego adresy z wiersza poleceń
    void start(const QStringList &urls, bool privateMode);

    QObject *profile() const;
    QObject *privateProfile() const;
    QVariantList bookmarks() const { return m_bookmarks; }
    int historyRevision() const { return m_historyRevision; }
    QVariantList downloads() const;
    int activeDownloads() const;
    QVariantList searchEngines() const;
    QString searchEngine() const { return m_engineId; }
    void setSearchEngine(const QString &id);
    QString searchName() const;
    bool restoreSession() const { return m_restoreSession; }
    void setRestoreSession(bool on);
    bool blockTrackers() const;
    void setBlockTrackers(bool on);
    bool forceDark() const { return m_forceDark; }
    void setForceDark(bool on);
    bool showFavoritesBar() const { return m_favoritesBar; }
    void setShowFavoritesBar(bool on);
    QString downloadDir() const;
    QString version() const;
    QString engineVersion() const;
    bool isDefault() const { return m_isDefault; }
    // Ustawia Przeglądarkę jako domyślną dla stron i linków (xdg-settings)
    Q_INVOKABLE void makeDefault();

    // ——— Wyszukiwarka i adresy ———
    Q_INVOKABLE QString searchUrl(const QString &query) const;
    Q_INVOKABLE QString suggestUrl(const QString &query) const;
    Q_INVOKABLE bool isSearchUrl(const QString &url) const;
    Q_INVOKABLE QString searchQuery(const QString &url) const;
    // To, co wpisano w pasek adresu → adres strony albo wyszukiwanie
    Q_INVOKABLE QString fixup(const QString &text) const;

    // ——— Historia ———
    Q_INVOKABLE void addVisit(const QString &url, const QString &title);
    Q_INVOKABLE void updateTitle(const QString &url, const QString &title);
    // Do podpowiedzi: najlepsze dopasowania (często odwiedzane i zaczynające się od wpisanego tekstu wyżej)
    Q_INVOKABLE QVariantList matchHistory(const QString &text, int limit) const;
    // Do strony Historia: od najnowszych, opcjonalnie filtrowane
    Q_INVOKABLE QVariantList history(const QString &text, int limit) const;
    Q_INVOKABLE QVariantList topSites(int limit) const;
    Q_INVOKABLE void removeHistory(const QString &url);
    Q_INVOKABLE void clearHistory(qint64 sinceMs);

    // ——— Ulubione ———
    Q_INVOKABLE bool isBookmarked(const QString &url) const;
    Q_INVOKABLE void addBookmark(const QString &url, const QString &title);
    Q_INVOKABLE void removeBookmark(const QString &url);
    Q_INVOKABLE void renameBookmark(const QString &url, const QString &title);
    Q_INVOKABLE void moveBookmark(int from, int to);

    // ——— Powiększenie zapamiętane dla każdej witryny ———
    Q_INVOKABLE qreal zoomFor(const QString &url) const;
    Q_INVOKABLE void setZoom(const QString &url, qreal zoom);

    // ——— Pobrane ———
    Q_INVOKABLE QString uniquePath(const QString &fileName) const;
    Q_INVOKABLE void removeDownload(QObject *item);
    Q_INVOKABLE void clearDownloads();

    // ——— Dane przeglądania ———
    Q_INVOKABLE void clearData(bool history, bool cookies, bool cache, bool downloads, qint64 sinceMs);

    // ——— Okna i sesja ———
    Q_INVOKABLE void openWindow(const QStringList &urls, bool privateMode);
    Q_INVOKABLE void windowClosed(QObject *window);
    Q_INVOKABLE void updateSession(int windowId, const QVariantList &tabs, int current);
    Q_INVOKABLE QString siteOf(const QString &url) const;

Q_SIGNALS:
    void bookmarksChanged();
    void historyChanged();
    void downloadsChanged();
    void settingsChanged();
    // Nowe pobieranie — okno, z którego przyszło, pokazuje dymek
    void downloadStarted(QObject *item, QObject *window);
    // Zablokowano element śledzący na stronie z tej witryny
    void trackerBlocked(const QString &site);

private Q_SLOTS:
    void onActionInvoked(uint id, const QString &action);

private:
    struct Visit {
        QString url;
        QString title;
        qint64 time = 0;
        int count = 0;
    };

    void setupProfile(QQuickWebEngineProfile *p, bool persistent);
    void onDownload(QQuickWebEngineDownloadRequest *request, bool keep);
    void onNotification(QWebEngineNotification *n);
    void onMessage(const QByteArray &data);
    QQuickWindow *createWindow(const QStringList &urls, bool privateMode, const QVariantList &tabs, int current);
    QVariantMap visitMap(const Visit &v) const;
    QString dataFile(const QString &name) const;
    void load();
    void migrateOld();
    void checkDefault();
    void scheduleSave() { m_saveTimer.start(); }
    void save();

    static Browser *s_instance;
    QQmlEngine *m_engine;
    QQuickWebEngineProfile *m_profile = nullptr;
    QQuickWebEngineProfile *m_private = nullptr;
    TrackerBlocker *m_blocker = nullptr;
    QLocalServer m_server;

    QList<Visit> m_visits;
    QHash<QString, int> m_visitIndex;
    int m_historyRevision = 0;
    QVariantList m_bookmarks;
    QList<DownloadItem *> m_downloads;

    QString m_engineId = QStringLiteral("google");
    bool m_restoreSession = true;
    bool m_forceDark = false;
    bool m_favoritesBar = false;
    bool m_isDefault = true;

    QList<QPointer<QQuickWindow>> m_windows;
    QPointer<QQuickWindow> m_lastActive;
    int m_nextWindowId = 1;
    QVariantMap m_session;              // „id okna” → { tabs, current }
    QHash<uint, QPointer<QWebEngineNotification>> m_notifications;

    QTimer m_saveTimer;
};
