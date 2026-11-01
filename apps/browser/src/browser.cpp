#include "browser.h"

#include "downloaditem.h"
#include "trackerblocker.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalSocket>
#include <QQmlComponent>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRegularExpression>
#include <QProcess>
#include <QSaveFile>
#include <QSettings>
#include <QStandardPaths>
#include <QUrl>
#include <QUrlQuery>
#include <QWebEngineCookieStore>
#include <QWebEngineNotification>
#include <QtWebEngineCore/qtwebenginecoreglobal.h>
#include <QtWebEngineQuick/QQuickWebEngineDownloadRequest>
#include <QtWebEngineQuick/QQuickWebEngineProfile>
#include <algorithm>
#include <cmath>

#include <unistd.h>

Browser *Browser::s_instance = nullptr;

static const QString nService = QStringLiteral("org.freedesktop.Notifications");
static const QString nPath = QStringLiteral("/org/freedesktop/Notifications");
static constexpr int maxVisits = 20000;

struct Engine {
    const char *id;
    const char *name;
    const char *search;     // %s = zapytanie
    const char *suggest;    // odpowiedź w formacie OpenSearch: ["zapytanie", ["podpowiedź", …]]
};
static const Engine engines[] = {
    {"google", "Google", "https://www.google.com/search?q=%s", "https://suggestqueries.google.com/complete/search?client=firefox&hl=pl&q=%s"},
    {"duckduckgo", "DuckDuckGo", "https://duckduckgo.com/?q=%s", "https://duckduckgo.com/ac/?type=list&kl=pl-pl&q=%s"},
    {"bing", "Bing", "https://www.bing.com/search?q=%s", "https://api.bing.com/osjson.aspx?query=%s"},
    {"brave", "Brave Search", "https://search.brave.com/search?q=%s", "https://search.brave.com/api/suggest?q=%s"},
    {"ecosia", "Ecosia", "https://www.ecosia.org/search?q=%s", "https://ac.ecosia.org/autocomplete?type=list&q=%s"},
};
static const Engine &engineById(const QString &id)
{
    for (const Engine &e : engines)
        if (id == QLatin1String(e.id))
            return e;
    return engines[0];
}

static QString serverName()
{
    return QStringLiteral("aster-browser-%1").arg(getuid());
}

Browser::Browser(QQmlEngine *engine, QObject *parent)
    : QObject(parent)
    , m_engine(engine)
{
    s_instance = this;
    m_saveTimer.setSingleShot(true);
    m_saveTimer.setInterval(1500);
    connect(&m_saveTimer, &QTimer::timeout, this, &Browser::save);
    connect(qApp, &QCoreApplication::aboutToQuit, this, &Browser::save);

    QSettings s;
    m_engineId = s.value(QStringLiteral("searchEngine"), m_engineId).toString();
    m_restoreSession = s.value(QStringLiteral("restoreSession"), true).toBool();
    m_forceDark = s.value(QStringLiteral("forceDark"), false).toBool();
    m_favoritesBar = s.value(QStringLiteral("favoritesBar"), false).toBool();

    m_blocker = new TrackerBlocker(this);
    m_blocker->setEnabled(s.value(QStringLiteral("blockTrackers"), true).toBool());
    connect(m_blocker, &TrackerBlocker::blocked, this, &Browser::trackerBlocked);

    m_profile = new QQuickWebEngineProfile(QStringLiteral("aster"), this);
    setupProfile(m_profile, true);
    m_private = new QQuickWebEngineProfile(this);       // bez nazwy = nic nie zapisuje na dysku
    setupProfile(m_private, false);

    QDBusConnection bus = QDBusConnection::sessionBus();
    bus.connect(nService, nPath, nService, QStringLiteral("ActionInvoked"), this, SLOT(onActionInvoked(uint, QString)));
    connect(qGuiApp, &QGuiApplication::focusWindowChanged, this, [this](QWindow *w) {
        for (const auto &win : std::as_const(m_windows))
            if (win == w && !win->property("privateMode").toBool())
                m_lastActive = win;
    });

    load();
    checkDefault();
}

Browser::~Browser()
{
    save();
    s_instance = nullptr;
}

Browser *Browser::create(QQmlEngine *, QJSEngine *)
{
    QJSEngine::setObjectOwnership(s_instance, QJSEngine::CppOwnership);
    return s_instance;
}

void Browser::setupProfile(QQuickWebEngineProfile *p, bool persistent)
{
    if (persistent) {
        p->setHttpCacheType(QQuickWebEngineProfile::DiskHttpCache);
        p->setPersistentCookiesPolicy(QQuickWebEngineProfile::AllowPersistentCookies);
        p->setPersistentPermissionsPolicy(QQuickWebEngineProfile::PersistentPermissionsPolicy::StoreOnDisk);
    }
    p->setHttpAcceptLanguage(QStringLiteral("pl-PL,pl;q=0.9,en-US;q=0.7,en;q=0.6"));
    // Strony traktują QtWebEngine jak zwykłego Chrome — bez dopisku silnika część z nich
    // (logowanie Google, banki) nie odsyła do „nieobsługiwanej przeglądarki”
    QString ua = p->httpUserAgent();
    ua.remove(QRegularExpression(QStringLiteral(" QtWebEngine/[0-9.]+")));
    p->setHttpUserAgent(ua);
    p->setUrlRequestInterceptor(m_blocker);
    p->setDownloadPath(downloadDir());
    const bool keep = persistent;
    connect(p, &QQuickWebEngineProfile::downloadRequested, this, [this, keep](QQuickWebEngineDownloadRequest *d) { onDownload(d, keep); });
    connect(p, &QQuickWebEngineProfile::presentNotification, this, &Browser::onNotification);
}

QObject *Browser::profile() const { return m_profile; }
QObject *Browser::privateProfile() const { return m_private; }

QString Browser::version() const { return QCoreApplication::applicationVersion(); }
QString Browser::engineVersion() const { return QString::fromLatin1(qWebEngineChromiumVersion()); }

void Browser::checkDefault()
{
    auto *p = new QProcess(this);
    connect(p, &QProcess::finished, this, [this, p](int code) {
        p->deleteLater();
        if (code != 0)
            return;         // nie da się sprawdzić — nie zawracamy głowy
        const bool def = p->readAllStandardOutput().trimmed() == "org.aster.browser.desktop";
        if (def != m_isDefault) {
            m_isDefault = def;
            Q_EMIT settingsChanged();
        }
    });
    connect(p, &QProcess::errorOccurred, p, &QObject::deleteLater);
    p->start(QStringLiteral("xdg-settings"), {QStringLiteral("get"), QStringLiteral("default-web-browser")});
}

void Browser::makeDefault()
{
    QProcess::execute(QStringLiteral("xdg-settings"), {QStringLiteral("set"), QStringLiteral("default-web-browser"), QStringLiteral("org.aster.browser.desktop")});
    for (const char *mime : {"x-scheme-handler/http", "x-scheme-handler/https", "text/html"})
        QProcess::execute(QStringLiteral("xdg-mime"), {QStringLiteral("default"), QStringLiteral("org.aster.browser.desktop"), QString::fromLatin1(mime)});
    checkDefault();
    Q_EMIT settingsChanged();
}

// ——— Jedna kopia programu ———

bool Browser::forwardToRunning(const QStringList &urls, bool privateMode)
{
    QLocalSocket socket;
    socket.connectToServer(serverName());
    if (!socket.waitForConnected(400))
        return false;
    const QJsonObject msg{{QStringLiteral("urls"), QJsonArray::fromStringList(urls)}, {QStringLiteral("private"), privateMode}};
    socket.write(QJsonDocument(msg).toJson(QJsonDocument::Compact));
    socket.waitForBytesWritten(400);
    socket.disconnectFromServer();
    return true;
}

void Browser::listen()
{
    QLocalServer::removeServer(serverName());
    m_server.listen(serverName());
    connect(&m_server, &QLocalServer::newConnection, this, [this] {
        while (QLocalSocket *s = m_server.nextPendingConnection()) {
            connect(s, &QLocalSocket::disconnected, s, &QObject::deleteLater);
            connect(s, &QLocalSocket::readyRead, this, [this, s] { onMessage(s->readAll()); });
        }
    });
}

void Browser::onMessage(const QByteArray &data)
{
    const QJsonObject msg = QJsonDocument::fromJson(data).object();
    QStringList urls;
    for (const QJsonValue &v : msg.value(QStringLiteral("urls")).toArray())
        urls << v.toString();
    const bool priv = msg.value(QStringLiteral("private")).toBool();
    // Linki z innych programów trafiają jako nowe karty do ostatniego okna (jak w Chrome)
    if (!priv && !urls.isEmpty() && m_lastActive && m_lastActive->isVisible()) {
        QMetaObject::invokeMethod(m_lastActive, "openUrls", Q_ARG(QVariant, QVariant(urls)));
        m_lastActive->raise();
        m_lastActive->requestActivate();
        return;
    }
    openWindow(urls, priv);
}

void Browser::start(const QStringList &urls, bool privateMode)
{
    if (privateMode) {
        openWindow(urls, true);
        return;
    }
    const QVariantMap saved = m_session;
    m_session.clear();
    bool first = true;
    if (m_restoreSession) {
        for (const QVariant &v : saved) {
            const QVariantMap w = v.toMap();
            const QVariantList tabs = w.value(QStringLiteral("tabs")).toList();
            if (tabs.isEmpty())
                continue;
            createWindow(first ? urls : QStringList(), false, tabs, w.value(QStringLiteral("current")).toInt());
            first = false;
        }
    }
    if (first)
        createWindow(urls, false, {}, 0);
}

void Browser::openWindow(const QStringList &urls, bool privateMode)
{
    createWindow(urls, privateMode, {}, 0);
}

QQuickWindow *Browser::createWindow(const QStringList &urls, bool privateMode, const QVariantList &tabs, int current)
{
    QQmlComponent component(m_engine, QStringLiteral("Aster.Browser"), QStringLiteral("Main"));
    QObject *obj = component.createWithInitialProperties({{QStringLiteral("startUrls"), urls},
                                                          {QStringLiteral("privateMode"), privateMode},
                                                          {QStringLiteral("windowId"), m_nextWindowId++},
                                                          {QStringLiteral("restoreTabs"), tabs},
                                                          {QStringLiteral("restoreCurrent"), current}});
    auto *window = qobject_cast<QQuickWindow *>(obj);
    if (!window) {
        qWarning("%s", qPrintable(component.errorString()));
        delete obj;
        return nullptr;
    }
    m_windows.append(window);
    if (!privateMode)
        m_lastActive = window;
    return window;
}

void Browser::windowClosed(QObject *window)
{
    auto *w = qobject_cast<QQuickWindow *>(window);
    if (!w)
        return;
    m_windows.removeAll(w);
    m_windows.removeAll(nullptr);
    // Zamknięte okno znika z sesji, chyba że było ostatnim zwykłym — wtedy wraca przy następnym uruchomieniu
    const bool othersLeft = std::any_of(m_windows.cbegin(), m_windows.cend(), [](const QPointer<QQuickWindow> &o) {
        return o && !o->property("privateMode").toBool();
    });
    if (othersLeft) {
        m_session.remove(QString::number(w->property("windowId").toInt()));
        scheduleSave();
    }
    w->deleteLater();
    if (m_windows.isEmpty()) {
        save();
        QCoreApplication::quit();
    }
}

void Browser::updateSession(int windowId, const QVariantList &tabs, int current)
{
    m_session.insert(QString::number(windowId), QVariantMap{{QStringLiteral("tabs"), tabs}, {QStringLiteral("current"), current}});
    scheduleSave();
}

// ——— Ustawienia ———

QVariantList Browser::searchEngines() const
{
    QVariantList out;
    for (const Engine &e : engines)
        out << QVariantMap{{QStringLiteral("id"), QString::fromLatin1(e.id)}, {QStringLiteral("name"), QString::fromUtf8(e.name)}};
    return out;
}

void Browser::setSearchEngine(const QString &id)
{
    if (id == m_engineId)
        return;
    m_engineId = QString::fromLatin1(engineById(id).id);
    QSettings().setValue(QStringLiteral("searchEngine"), m_engineId);
    Q_EMIT settingsChanged();
}

QString Browser::searchName() const { return QString::fromUtf8(engineById(m_engineId).name); }

void Browser::setRestoreSession(bool on)
{
    if (on == m_restoreSession)
        return;
    m_restoreSession = on;
    QSettings().setValue(QStringLiteral("restoreSession"), on);
    Q_EMIT settingsChanged();
}

bool Browser::blockTrackers() const { return m_blocker->enabled(); }

void Browser::setBlockTrackers(bool on)
{
    if (on == m_blocker->enabled())
        return;
    m_blocker->setEnabled(on);
    QSettings().setValue(QStringLiteral("blockTrackers"), on);
    Q_EMIT settingsChanged();
}

void Browser::setForceDark(bool on)
{
    if (on == m_forceDark)
        return;
    m_forceDark = on;
    QSettings().setValue(QStringLiteral("forceDark"), on);
    Q_EMIT settingsChanged();
}

void Browser::setShowFavoritesBar(bool on)
{
    if (on == m_favoritesBar)
        return;
    m_favoritesBar = on;
    QSettings().setValue(QStringLiteral("favoritesBar"), on);
    Q_EMIT settingsChanged();
}

QString Browser::downloadDir() const
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    return dir.isEmpty() ? QDir::homePath() : dir;
}

// ——— Wyszukiwarka i adresy ———

QString Browser::searchUrl(const QString &query) const
{
    return QString::fromLatin1(engineById(m_engineId).search).replace(QLatin1String("%s"), QString::fromLatin1(QUrl::toPercentEncoding(query)));
}

QString Browser::suggestUrl(const QString &query) const
{
    return QString::fromLatin1(engineById(m_engineId).suggest).replace(QLatin1String("%s"), QString::fromLatin1(QUrl::toPercentEncoding(query)));
}

bool Browser::isSearchUrl(const QString &url) const
{
    return !searchQuery(url).isEmpty();
}

QString Browser::searchQuery(const QString &url) const
{
    const QUrl u(url);
    for (const Engine &e : engines) {
        const QUrl s(QString::fromLatin1(e.search));
        if (u.host() == s.host() && u.path() == s.path())
            return QUrlQuery(u).queryItemValue(QStringLiteral("q"), QUrl::FullyDecoded).replace(QLatin1Char('+'), QLatin1Char(' '));
    }
    return QString();
}

QString Browser::fixup(const QString &input) const
{
    const QString t = input.trimmed();
    if (t.isEmpty())
        return QString();
    static const QRegularExpression scheme(QStringLiteral("^(https?|file|ftp|about|data|view-source|chrome|blob|aster):"), QRegularExpression::CaseInsensitiveOption);
    if (scheme.match(t).hasMatch())
        return t;
    if (t.startsWith(QLatin1Char('/')) || t.startsWith(QLatin1Char('~')))
        return QUrl::fromLocalFile(t.startsWith(QLatin1Char('~')) ? QDir::homePath() + t.mid(1) : t).toString();
    static const QRegularExpression host(QStringLiteral("^([\\w-]+\\.)+[a-z]{2,}(:\\d+)?([/?#].*)?$"), QRegularExpression::CaseInsensitiveOption);
    static const QRegularExpression local(QStringLiteral("^(localhost|\\d{1,3}(\\.\\d{1,3}){3}|\\[[0-9a-f:]+\\])(:\\d+)?([/?#].*)?$"), QRegularExpression::CaseInsensitiveOption);
    if (!t.contains(QLatin1Char(' '))) {
        if (local.match(t).hasMatch())
            return QStringLiteral("http://") + t;
        if (host.match(t).hasMatch())
            return QStringLiteral("https://") + t;
    }
    return searchUrl(t);
}

QString Browser::siteOf(const QString &url) const
{
    return TrackerBlocker::siteOf(QUrl(url).host().toLower());
}

// ——— Historia ———

static bool remembered(const QString &url)
{
    return url.startsWith(QLatin1String("http://")) || url.startsWith(QLatin1String("https://")) || url.startsWith(QLatin1String("file://"));
}

void Browser::addVisit(const QString &url, const QString &title)
{
    if (!remembered(url))
        return;
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    const auto it = m_visitIndex.constFind(url);
    if (it != m_visitIndex.cend()) {
        Visit &v = m_visits[*it];
        v.time = now;
        v.count++;
        if (!title.isEmpty())
            v.title = title;
    } else {
        m_visits.append({url, title, now, 1});
        m_visitIndex.insert(url, m_visits.size() - 1);
        if (m_visits.size() > maxVisits) {
            // Najstarsze odpadają
            std::sort(m_visits.begin(), m_visits.end(), [](const Visit &a, const Visit &b) { return a.time > b.time; });
            m_visits.resize(maxVisits * 9 / 10);
            m_visitIndex.clear();
            for (int i = 0; i < m_visits.size(); ++i)
                m_visitIndex.insert(m_visits.at(i).url, i);
        }
    }
    m_historyRevision++;
    Q_EMIT historyChanged();
    scheduleSave();
}

void Browser::updateTitle(const QString &url, const QString &title)
{
    const auto it = m_visitIndex.constFind(url);
    if (it == m_visitIndex.cend() || title.isEmpty() || m_visits.at(*it).title == title)
        return;
    m_visits[*it].title = title;
    m_historyRevision++;
    Q_EMIT historyChanged();
    scheduleSave();
}

QVariantMap Browser::visitMap(const Visit &v) const
{
    return {{QStringLiteral("url"), v.url}, {QStringLiteral("title"), v.title}, {QStringLiteral("time"), v.time}, {QStringLiteral("count"), v.count}};
}

static QString bare(const QString &url)
{
    QString s = url;
    s.remove(QRegularExpression(QStringLiteral("^[a-z]+://(www\\.)?")));
    return s.toLower();
}

QVariantList Browser::matchHistory(const QString &text, int limit) const
{
    const QString q = text.trimmed().toLower();
    if (q.isEmpty())
        return {};
    const QStringList words = q.split(QLatin1Char(' '), Qt::SkipEmptyParts);
    struct Hit { const Visit *v; double score; };
    QList<Hit> hits;
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    for (const Visit &v : m_visits) {
        if (isSearchUrl(v.url))
            continue;
        const QString b = bare(v.url);
        const QString t = v.title.toLower();
        bool all = true;
        for (const QString &w : words)
            if (!b.contains(w) && !t.contains(w)) { all = false; break; }
        if (!all)
            continue;
        const double days = double(now - v.time) / 86400000.0;
        double score = std::log2(1.0 + v.count) * 2.0 + 4.0 / (1.0 + days);
        if (b.startsWith(q))
            score += 10;                    // „you” → youtube.com
        if (!b.contains(QLatin1Char('/')) || b.endsWith(QLatin1Char('/')))
            score += 2;                     // strona główna przed podstronami
        hits.append({&v, score});
    }
    std::sort(hits.begin(), hits.end(), [](const Hit &a, const Hit &b) { return a.score > b.score; });
    QVariantList out;
    for (const Hit &h : std::as_const(hits)) {
        if (out.size() >= limit)
            break;
        out << visitMap(*h.v);
    }
    return out;
}

QVariantList Browser::history(const QString &text, int limit) const
{
    const QString q = text.trimmed().toLower();
    QList<const Visit *> list;
    for (const Visit &v : m_visits)
        if (q.isEmpty() || v.url.toLower().contains(q) || v.title.toLower().contains(q))
            list << &v;
    std::sort(list.begin(), list.end(), [](const Visit *a, const Visit *b) { return a->time > b->time; });
    QVariantList out;
    for (const Visit *v : std::as_const(list)) {
        if (out.size() >= limit)
            break;
        out << visitMap(*v);
    }
    return out;
}

QVariantList Browser::topSites(int limit) const
{
    struct Site { QString url; QString title; double score = 0; int best = 0; };
    QHash<QString, Site> sites;
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    for (const Visit &v : m_visits) {
        if (isSearchUrl(v.url) || !v.url.startsWith(QLatin1String("http")))
            continue;
        const QString host = QUrl(v.url).host().remove(QRegularExpression(QStringLiteral("^www\\.")));
        Site &s = sites[host];
        const double days = double(now - v.time) / 86400000.0;
        s.score += v.count / (1.0 + days / 14.0);
        if (v.count > s.best || s.url.isEmpty()) {
            s.best = v.count;
            // Strona główna witryny zamiast przypadkowej podstrony
            const QUrl u(v.url);
            s.url = u.scheme() + QStringLiteral("://") + u.host() + QLatin1Char('/');
            s.title = v.title;
        }
    }
    QList<Site> list = sites.values();
    std::sort(list.begin(), list.end(), [](const Site &a, const Site &b) { return a.score > b.score; });
    QVariantList out;
    for (const Site &s : std::as_const(list)) {
        if (out.size() >= limit)
            break;
        out << QVariantMap{{QStringLiteral("url"), s.url}, {QStringLiteral("title"), s.title}};
    }
    return out;
}

void Browser::removeHistory(const QString &url)
{
    const auto it = m_visitIndex.constFind(url);
    if (it == m_visitIndex.cend())
        return;
    m_visits.removeAt(*it);
    m_visitIndex.clear();
    for (int i = 0; i < m_visits.size(); ++i)
        m_visitIndex.insert(m_visits.at(i).url, i);
    m_historyRevision++;
    Q_EMIT historyChanged();
    scheduleSave();
}

void Browser::clearHistory(qint64 sinceMs)
{
    m_visits.erase(std::remove_if(m_visits.begin(), m_visits.end(), [sinceMs](const Visit &v) { return v.time >= sinceMs; }), m_visits.end());
    m_visitIndex.clear();
    for (int i = 0; i < m_visits.size(); ++i)
        m_visitIndex.insert(m_visits.at(i).url, i);
    m_historyRevision++;
    Q_EMIT historyChanged();
    scheduleSave();
}

// ——— Ulubione ———

static int bookmarkIndex(const QVariantList &list, const QString &url)
{
    for (int i = 0; i < list.size(); ++i)
        if (list.at(i).toMap().value(QStringLiteral("url")).toString() == url)
            return i;
    return -1;
}

bool Browser::isBookmarked(const QString &url) const { return bookmarkIndex(m_bookmarks, url) >= 0; }

void Browser::addBookmark(const QString &url, const QString &title)
{
    if (url.isEmpty() || isBookmarked(url))
        return;
    m_bookmarks << QVariantMap{{QStringLiteral("url"), url}, {QStringLiteral("title"), title.isEmpty() ? QUrl(url).host() : title}};
    Q_EMIT bookmarksChanged();
    scheduleSave();
}

void Browser::removeBookmark(const QString &url)
{
    const int i = bookmarkIndex(m_bookmarks, url);
    if (i < 0)
        return;
    m_bookmarks.removeAt(i);
    Q_EMIT bookmarksChanged();
    scheduleSave();
}

void Browser::renameBookmark(const QString &url, const QString &title)
{
    const int i = bookmarkIndex(m_bookmarks, url);
    if (i < 0 || title.trimmed().isEmpty())
        return;
    QVariantMap m = m_bookmarks.at(i).toMap();
    m.insert(QStringLiteral("title"), title.trimmed());
    m_bookmarks[i] = m;
    Q_EMIT bookmarksChanged();
    scheduleSave();
}

void Browser::moveBookmark(int from, int to)
{
    if (from < 0 || from >= m_bookmarks.size() || to < 0 || to >= m_bookmarks.size() || from == to)
        return;
    m_bookmarks.move(from, to);
    Q_EMIT bookmarksChanged();
    scheduleSave();
}

// ——— Powiększenie ———

static QString zoomKey(const QString &url)
{
    return QStringLiteral("zoom/") + QUrl(url).host();
}

qreal Browser::zoomFor(const QString &url) const
{
    return QSettings().value(zoomKey(url), 1.0).toReal();
}

void Browser::setZoom(const QString &url, qreal zoom)
{
    if (QUrl(url).host().isEmpty())
        return;
    QSettings s;
    if (qFuzzyCompare(zoom, 1.0))
        s.remove(zoomKey(url));
    else
        s.setValue(zoomKey(url), zoom);
}

// ——— Pobrane ———

QString Browser::uniquePath(const QString &fileName) const
{
    const QDir dir(downloadDir());
    QString name = QFileInfo(fileName).fileName();
    if (name.isEmpty())
        name = QStringLiteral("plik");
    if (!dir.exists(name))
        return dir.filePath(name);
    // „raport.pdf” → „raport (1).pdf”, „archiwum.tar.gz” → „archiwum (1).tar.gz”
    const QFileInfo fi(name);
    QString base = fi.completeBaseName(), ext = fi.suffix();
    if (base.endsWith(QLatin1String(".tar"))) {
        base.chop(4);
        ext = QStringLiteral("tar.") + ext;
    }
    for (int i = 1;; ++i) {
        const QString candidate = base + QStringLiteral(" (%1)").arg(i) + (ext.isEmpty() ? QString() : QLatin1Char('.') + ext);
        if (!dir.exists(candidate))
            return dir.filePath(candidate);
    }
}

void Browser::onDownload(QQuickWebEngineDownloadRequest *request, bool keep)
{
    if (!request->isSavePageDownload()) {
        const QString path = uniquePath(request->downloadFileName());
        request->setDownloadDirectory(QFileInfo(path).absolutePath());
        request->setDownloadFileName(QFileInfo(path).fileName());
    }
    request->accept();
    auto *item = new DownloadItem(request, keep, this);
    connect(item, &DownloadItem::changed, this, [this] { Q_EMIT downloadsChanged(); });
    connect(item, &DownloadItem::finished, this, [this] { scheduleSave(); });
    m_downloads.prepend(item);
    Q_EMIT downloadsChanged();
    scheduleSave();

    QObject *window = nullptr;
    if (auto *view = qobject_cast<QQuickItem *>(request->property("view").value<QObject *>()))
        window = view->window();
    Q_EMIT downloadStarted(item, window);
}

QVariantList Browser::downloads() const
{
    QVariantList out;
    for (DownloadItem *d : m_downloads)
        out << QVariant::fromValue(static_cast<QObject *>(d));
    return out;
}

int Browser::activeDownloads() const
{
    return int(std::count_if(m_downloads.cbegin(), m_downloads.cend(), [](DownloadItem *d) { return d->active(); }));
}

void Browser::removeDownload(QObject *item)
{
    auto *d = qobject_cast<DownloadItem *>(item);
    if (!d || !m_downloads.contains(d))
        return;
    if (d->active())
        d->cancel();
    m_downloads.removeAll(d);
    d->deleteLater();
    Q_EMIT downloadsChanged();
    scheduleSave();
}

void Browser::clearDownloads()
{
    for (DownloadItem *d : m_downloads.toList())
        if (!d->active()) {
            m_downloads.removeAll(d);
            d->deleteLater();
        }
    Q_EMIT downloadsChanged();
    scheduleSave();
}

// ——— Dane przeglądania ———

void Browser::clearData(bool history, bool cookies, bool cache, bool downloadList, qint64 sinceMs)
{
    if (history)
        clearHistory(sinceMs);
    if (cookies)
        m_profile->cookieStore()->deleteAllCookies();
    if (cache)
        m_profile->clearHttpCache();
    if (downloadList)
        clearDownloads();
}

// ——— Powiadomienia stron jako systemowe ———

void Browser::onNotification(QWebEngineNotification *n)
{
    // Przejmujemy powiadomienie od silnika — żyje, dopóki nie zniknie z ekranu
    QJSEngine::setObjectOwnership(n, QJSEngine::CppOwnership);
    n->setParent(this);
    const QString site = QUrl(n->origin()).host().remove(QRegularExpression(QStringLiteral("^www\\.")));
    QDBusMessage msg = QDBusMessage::createMethodCall(nService, nPath, nService, QStringLiteral("Notify"));
    msg << QStringLiteral("Przeglądarka") << uint(0) << QStringLiteral("internet-web-browser") << n->title()
        << (n->message().isEmpty() ? site : n->message() + QStringLiteral("\n") + site)
        << QStringList{QStringLiteral("default"), QStringLiteral("Otwórz")}
        << QVariantMap{{QStringLiteral("desktop-entry"), QStringLiteral("org.aster.browser")}} << int(-1);
    const QDBusReply<uint> reply = QDBusConnection::sessionBus().call(msg, QDBus::Block, 2000);
    if (!reply.isValid()) {
        n->deleteLater();
        return;
    }
    const uint id = reply.value();
    m_notifications.insert(id, n);
    n->show();
    connect(n, &QWebEngineNotification::closed, this, [this, id, n] {
        QDBusMessage close = QDBusMessage::createMethodCall(nService, nPath, nService, QStringLiteral("CloseNotification"));
        close << id;
        QDBusConnection::sessionBus().asyncCall(close);
        m_notifications.remove(id);
        n->deleteLater();
    });
}

void Browser::onActionInvoked(uint id, const QString &action)
{
    const QPointer<QWebEngineNotification> n = m_notifications.value(id);
    if (!n || action != QLatin1String("default"))
        return;
    n->click();
    if (m_lastActive) {
        m_lastActive->raise();
        m_lastActive->requestActivate();
    }
}

// ——— Zapis na dysku ———

QString Browser::dataFile(const QString &name) const
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(dir);
    return QDir(dir).filePath(name);
}

static QJsonDocument readJson(const QString &path)
{
    QFile f(path);
    return f.open(QIODevice::ReadOnly) ? QJsonDocument::fromJson(f.readAll()) : QJsonDocument();
}

static void writeJson(const QString &path, const QJsonDocument &doc)
{
    // Zapis atomowy: przy awarii w połowie zostaje poprzednia wersja pliku
    QSaveFile f(path);
    if (f.open(QIODevice::WriteOnly)) {
        f.write(doc.toJson(QJsonDocument::Compact));
        f.commit();
    }
}

void Browser::load()
{
    const QJsonArray visits = readJson(dataFile(QStringLiteral("history.json"))).array();
    for (const QJsonValue &v : visits) {
        const QJsonObject o = v.toObject();
        const QString url = o.value(QStringLiteral("u")).toString();
        if (url.isEmpty() || m_visitIndex.contains(url))
            continue;
        m_visits.append({url, o.value(QStringLiteral("t")).toString(), qint64(o.value(QStringLiteral("d")).toDouble()), o.value(QStringLiteral("c")).toInt(1)});
        m_visitIndex.insert(url, m_visits.size() - 1);
    }
    const QJsonDocument bm = readJson(dataFile(QStringLiteral("bookmarks.json")));
    if (bm.isArray())
        m_bookmarks = bm.array().toVariantList();
    else
        migrateOld();
    for (const QJsonValue &v : readJson(dataFile(QStringLiteral("downloads.json"))).array())
        m_downloads << new DownloadItem(v.toObject().toVariantMap(), this);
    m_session = readJson(dataFile(QStringLiteral("session.json"))).object().toVariantMap();
}

// Ulubione i historia z pierwszej wersji przeglądarki (QtCore Settings, kategoria „browser”)
void Browser::migrateOld()
{
    QSettings s;
    s.beginGroup(QStringLiteral("browser"));
    const QVariant fav = s.value(QStringLiteral("favorites"));
    const QVariant hist = s.value(QStringLiteral("history"));
    s.endGroup();
    const auto list = [](const QVariant &v) {
        if (v.typeId() == QMetaType::QString)
            return QJsonDocument::fromJson(v.toString().toUtf8()).array().toVariantList();
        return v.toList();
    };
    m_bookmarks = list(fav);
    if (m_bookmarks.isEmpty())
        m_bookmarks = {
            QVariantMap{{QStringLiteral("url"), QStringLiteral("https://www.google.com/")}, {QStringLiteral("title"), QStringLiteral("Google")}},
            QVariantMap{{QStringLiteral("url"), QStringLiteral("https://www.youtube.com/")}, {QStringLiteral("title"), QStringLiteral("YouTube")}},
            QVariantMap{{QStringLiteral("url"), QStringLiteral("https://pl.wikipedia.org/")}, {QStringLiteral("title"), QStringLiteral("Wikipedia")}},
            QVariantMap{{QStringLiteral("url"), QStringLiteral("https://allegro.pl/")}, {QStringLiteral("title"), QStringLiteral("Allegro")}},
            QVariantMap{{QStringLiteral("url"), QStringLiteral("https://mail.google.com/")}, {QStringLiteral("title"), QStringLiteral("Gmail")}},
            QVariantMap{{QStringLiteral("url"), QStringLiteral("https://www.onet.pl/")}, {QStringLiteral("title"), QStringLiteral("Onet")}},
        };
    for (const QVariant &v : list(hist)) {
        const QVariantMap h = v.toMap();
        const QString url = h.value(QStringLiteral("url")).toString();
        if (!remembered(url) || m_visitIndex.contains(url))
            continue;
        m_visits.append({url, h.value(QStringLiteral("title")).toString(), h.value(QStringLiteral("time")).toLongLong(), 1});
        m_visitIndex.insert(url, m_visits.size() - 1);
    }
    scheduleSave();
}

void Browser::save()
{
    m_saveTimer.stop();
    QJsonArray visits;
    for (const Visit &v : std::as_const(m_visits))
        visits.append(QJsonObject{{QStringLiteral("u"), v.url}, {QStringLiteral("t"), v.title}, {QStringLiteral("d"), double(v.time)}, {QStringLiteral("c"), v.count}});
    writeJson(dataFile(QStringLiteral("history.json")), QJsonDocument(visits));
    writeJson(dataFile(QStringLiteral("bookmarks.json")), QJsonDocument(QJsonArray::fromVariantList(m_bookmarks)));
    QJsonArray downloads;
    for (DownloadItem *d : std::as_const(m_downloads))
        if (d->keep() && downloads.size() < 200)
            downloads.append(QJsonObject::fromVariantMap(d->record()));
    writeJson(dataFile(QStringLiteral("downloads.json")), QJsonDocument(downloads));
    writeJson(dataFile(QStringLiteral("session.json")), QJsonDocument(QJsonObject::fromVariantMap(m_session)));
}
