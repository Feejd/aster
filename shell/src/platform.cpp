#include "platform.h"

#include <KIO/ApplicationLauncherJob>
#include <KIO/OpenUrlJob>
#include <KApplicationTrader>
#include <KService>
#include <KSycoca>
#include <KWindowEffects>
#include <LayerShellQt/Window>
#include <notificationmanager/notification.h>
#include <notificationmanager/notifications.h>
#include <notificationmanager/server.h>

#include <QCollator>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDateTime>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QTemporaryDir>
#include <QHash>
#include <QMimeDatabase>
#include <QPainterPath>
#include <QProcess>
#include <QQuickWindow>
#include <QRegion>
#include <QStandardPaths>
#include <QUrl>
#include <QXmlStreamReader>

#include <algorithm>
#include <pwd.h>
#include <unistd.h>

using LayerWindow = LayerShellQt::Window;

Platform::Platform(QObject *parent)
    : QObject(parent)
{
    // Zajmujemy miejsce plasmashell na szynie D-Bus — KWin wywoła activateLauncherMenu() po Super.
    // Gdy plasmashell działa (zwykła sesja KDE), nazwy nie dostaniemy i nic się nie psuje.
    QDBusConnection bus = QDBusConnection::sessionBus();
    bus.registerObject(QStringLiteral("/PlasmaShell"), this, QDBusConnection::ExportScriptableSlots);
    bus.registerService(QStringLiteral("org.kde.plasmashell"));

    // Nowo zainstalowane / usunięte programy (baza KDE się przebudowuje)
    connect(KSycoca::self(), &KSycoca::databaseChanged, this, &Platform::applicationsChanged);

    // Liczby nieprzeczytanych od programów (komunikatory, poczta, aplikacje webowe Aster)
    bus.connect(QString(), QString(), QStringLiteral("com.canonical.Unity.LauncherEntry"), QStringLiteral("Update"), this,
                SLOT(onLauncherEntry(QString, QVariantMap)));

    // Serwer powiadomień (w zwykłej sesji KDE ma go plasmashell — wtedy init() się nie uda i nic nie robimy)
    using NotificationManager::Server;
    if (Server::self().init()) {
        connect(&Server::self(), &Server::notificationAdded, this, [this](const NotificationManager::Notification &n) {
            QString image;
            if (!n.image().isNull()) {
                static QTemporaryDir dir;
                image = dir.path() + QStringLiteral("/n-%1.png").arg(n.id());
                n.image().save(image);
                image = QUrl::fromLocalFile(image).toString();
            } else if (n.icon().startsWith(QLatin1Char('/'))) {
                image = QUrl::fromLocalFile(n.icon()).toString();
            }
            Q_EMIT notificationPosted({
                {QStringLiteral("id"), n.id()},
                {QStringLiteral("appName"), n.applicationName()},
                {QStringLiteral("icon"), n.icon().startsWith(QLatin1Char('/')) ? QString() : (n.icon().isEmpty() ? n.applicationIconName() : n.icon())},
                {QStringLiteral("image"), image},
                {QStringLiteral("summary"), n.summary()},
                {QStringLiteral("body"), n.body()},
            });
        });
        connect(&Server::self(), &Server::notificationRemoved, this, [this](uint id) { Q_EMIT notificationClosed(id); });
    }
}

void Platform::onLauncherEntry(const QString &uri, const QVariantMap &properties)
{
    // „application://firefox.desktop” → „firefox”
    QString id = uri.section(QLatin1Char('/'), -1);
    if (id.endsWith(QLatin1String(".desktop")))
        id.chop(8);
    const bool visible = properties.value(QStringLiteral("count-visible"), true).toBool();
    const qint64 count = properties.value(QStringLiteral("count")).toLongLong();
    if (visible && count > 0)
        m_badges.insert(id, count);
    else
        m_badges.remove(id);
    Q_EMIT badgesChanged();
}

void Platform::activateNotification(uint id)
{
    NotificationManager::Server::self().invokeAction(id, QStringLiteral("default"), QString(), NotificationManager::Notifications::Close);
}

void Platform::dismissNotification(uint id)
{
    NotificationManager::Server::self().closeNotification(id, NotificationManager::Server::CloseReason::DismissedByUser);
}

// Kategoria Aster z kategorii freedesktop programu (pierwsze dopasowanie wygrywa)
static QString asterCategory(const QStringList &cats)
{
    static const QList<QPair<QString, QStringList>> map{
        {QStringLiteral("gry"), {QStringLiteral("Game")}},
        {QStringLiteral("internet"), {QStringLiteral("Network"), QStringLiteral("WebBrowser"), QStringLiteral("Email"), QStringLiteral("Chat"), QStringLiteral("InstantMessaging")}},
        {QStringLiteral("biuro"), {QStringLiteral("Office"), QStringLiteral("WordProcessor"), QStringLiteral("Spreadsheet"), QStringLiteral("Presentation"), QStringLiteral("Calendar")}},
        {QStringLiteral("grafika"), {QStringLiteral("Graphics"), QStringLiteral("Photography")}},
        {QStringLiteral("multimedia"), {QStringLiteral("AudioVideo"), QStringLiteral("Audio"), QStringLiteral("Video"), QStringLiteral("Music")}},
        {QStringLiteral("programowanie"), {QStringLiteral("Development"), QStringLiteral("IDE")}},
        {QStringLiteral("edukacja"), {QStringLiteral("Education"), QStringLiteral("Science")}},
        {QStringLiteral("system"), {QStringLiteral("Settings"), QStringLiteral("System"), QStringLiteral("PackageManager")}},
        {QStringLiteral("narzedzia"), {QStringLiteral("Utility"), QStringLiteral("Accessories"), QStringLiteral("FileManager")}},
    };
    for (const auto &[id, keys] : map)
        for (const QString &k : keys)
            if (cats.contains(k))
                return id;
    return QStringLiteral("inne");
}

QVariantList Platform::applications() const
{
    const KService::List services = KApplicationTrader::query([](const KService::Ptr &s) {
        return !s->noDisplay() && s->showInCurrentDesktop() && s->showOnCurrentPlatform();
    });
    QList<KService::Ptr> list(services.cbegin(), services.cend());
    QCollator collator;
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    collator.setNumericMode(true);
    std::sort(list.begin(), list.end(), [&](const KService::Ptr &a, const KService::Ptr &b) {
        return collator.compare(a->name(), b->name()) < 0;
    });
    QVariantList out;
    for (const KService::Ptr &s : std::as_const(list)) {
        out.append(QVariantMap{
            {QStringLiteral("id"), s->desktopEntryName()},
            {QStringLiteral("name"), s->name()},
            {QStringLiteral("icon"), s->icon()},
            {QStringLiteral("generic"), s->genericName()},
            {QStringLiteral("category"), asterCategory(s->categories())},
        });
    }
    return out;
}

QString Platform::userName() const
{
    if (const passwd *pw = getpwuid(getuid())) {
        const QString gecos = QString::fromLocal8Bit(pw->pw_gecos).section(QLatin1Char(','), 0, 0).trimmed();
        return gecos.isEmpty() ? QString::fromLocal8Bit(pw->pw_name) : gecos;
    }
    return QString::fromLocal8Bit(qgetenv("USER"));
}

QVariantMap Platform::appInfo(const QString &desktopId) const
{
    const KService::Ptr service = KService::serviceByDesktopName(desktopId);
    if (!service)
        return {{QStringLiteral("valid"), false}};
    return {
        {QStringLiteral("valid"), true},
        {QStringLiteral("name"), service->name()},
        {QStringLiteral("icon"), service->icon()},
    };
}

void Platform::launchApp(const QString &desktopId)
{
    const KService::Ptr service = KService::serviceByDesktopName(desktopId);
    if (!service)
        return;
    auto *job = new KIO::ApplicationLauncherJob(service);
    job->start();
}

QVariantList Platform::recentFiles(int count) const
{
    QFile file(QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)
               + QStringLiteral("/recently-used.xbel"));
    if (!file.open(QIODevice::ReadOnly))
        return {};

    struct Entry {
        QUrl url;
        QDateTime modified;
        QString mime;
    };
    QList<Entry> entries;
    QXmlStreamReader xml(&file);
    while (!xml.atEnd()) {
        xml.readNext();
        if (!xml.isStartElement())
            continue;
        if (xml.name() == QLatin1String("bookmark")) {
            const auto a = xml.attributes();
            const QString stamp = a.value(QLatin1String("visited")).isEmpty() ? a.value(QLatin1String("modified")).toString()
                                                                              : a.value(QLatin1String("visited")).toString();
            entries.append({QUrl(a.value(QLatin1String("href")).toString()), QDateTime::fromString(stamp, Qt::ISODate), {}});
        } else if (xml.name() == QLatin1String("mime-type") && !entries.isEmpty()) {
            entries.last().mime = xml.attributes().value(QLatin1String("type")).toString();
        }
    }

    std::sort(entries.begin(), entries.end(), [](const Entry &a, const Entry &b) { return a.modified > b.modified; });

    QMimeDatabase mimes;
    QVariantList out;
    for (const Entry &e : std::as_const(entries)) {
        if (out.size() >= count)
            break;
        if (!e.url.isLocalFile() || !QFileInfo::exists(e.url.toLocalFile()) || QFileInfo(e.url.toLocalFile()).isDir())
            continue;
        const QMimeType mime = e.mime.isEmpty() ? mimes.mimeTypeForFile(e.url.toLocalFile()) : mimes.mimeTypeForName(e.mime);
        out.append(QVariantMap{
            {QStringLiteral("name"), e.url.fileName()},
            {QStringLiteral("url"), e.url.toString()},
            {QStringLiteral("icon"), mime.iconName()},
            {QStringLiteral("modified"), e.modified.toLocalTime()},
        });
    }
    return out;
}

void Platform::openUrl(const QString &url)
{
    auto *job = new KIO::OpenUrlJob(QUrl(url));
    job->start();
}

void Platform::lockScreen()
{
    QDBusConnection::sessionBus().asyncCall(QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.ScreenSaver"), QStringLiteral("/ScreenSaver"),
        QStringLiteral("org.freedesktop.ScreenSaver"), QStringLiteral("Lock")));
}

void Platform::shutdownPrompt()
{
    QDBusConnection::sessionBus().asyncCall(QDBusMessage::createMethodCall(
        QStringLiteral("org.kde.LogoutPrompt"), QStringLiteral("/LogoutPrompt"),
        QStringLiteral("org.kde.LogoutPrompt"), QStringLiteral("promptShutDown")));
}

void Platform::activateLauncherMenu()
{
    Q_EMIT launcherRequested();
}

QString Platform::dataDir() const
{
    const QByteArray env = qgetenv("ASTER_DATA_DIR");
    if (!env.isEmpty())
        return QString::fromLocal8Bit(env);
    const QString found = QStandardPaths::locate(QStandardPaths::GenericDataLocation, QStringLiteral("aster"),
                                                 QStandardPaths::LocateDirectory);
    return found.isEmpty() ? QStringLiteral(ASTER_INSTALL_DATADIR) : found;
}

void Platform::makeLayer(QQuickWindow *window, const QString &layer, int anchors, int exclusiveZone,
                         const QString &keyboard, const QString &scope)
{
    if (!window)
        return;
    LayerWindow *lw = LayerWindow::get(window);
    if (!lw)
        return;

    static const QHash<QString, LayerWindow::Layer> layers{
        {QStringLiteral("background"), LayerWindow::LayerBackground},
        {QStringLiteral("bottom"), LayerWindow::LayerBottom},
        {QStringLiteral("top"), LayerWindow::LayerTop},
        {QStringLiteral("overlay"), LayerWindow::LayerOverlay},
    };
    static const QHash<QString, LayerWindow::KeyboardInteractivity> keyboards{
        {QStringLiteral("none"), LayerWindow::KeyboardInteractivityNone},
        {QStringLiteral("exclusive"), LayerWindow::KeyboardInteractivityExclusive},
        {QStringLiteral("ondemand"), LayerWindow::KeyboardInteractivityOnDemand},
    };

    lw->setLayer(layers.value(layer, LayerWindow::LayerTop));
    lw->setAnchors(LayerWindow::Anchors::fromInt(anchors));
    lw->setExclusiveZone(exclusiveZone);
    lw->setKeyboardInteractivity(keyboards.value(keyboard, LayerWindow::KeyboardInteractivityNone));
    lw->setScope(scope);
}

static QRegion roundedRegion(const QVariantList &rects)
{
    QRegion region;
    for (const QVariant &v : rects) {
        const QVariantMap m = v.toMap();
        const QRectF r(m.value(QStringLiteral("x")).toReal(), m.value(QStringLiteral("y")).toReal(),
                       m.value(QStringLiteral("w")).toReal(), m.value(QStringLiteral("h")).toReal());
        const qreal radius = m.value(QStringLiteral("r")).toReal();
        QPainterPath path;
        path.addRoundedRect(r, radius, radius);
        region += QRegion(path.toFillPolygon().toPolygon());
    }
    return region;
}

void Platform::setBlur(QQuickWindow *window, const QVariantList &rects)
{
    if (!window)
        return;
    blurRegions[window] = rects;
    const QRegion region = roundedRegion(rects);
    KWindowEffects::enableBlurBehind(window, !region.isEmpty(), region);
}

void Platform::setInputRegion(QQuickWindow *window, const QVariantList &rects)
{
    if (!window)
        return;
    // Na Waylandzie maska okna Qt staje się regionem wejścia powierzchni
    window->setMask(roundedRegion(rects));
}

void Platform::run(const QString &program, const QStringList &args)
{
    QProcess::startDetached(program, args);
}
