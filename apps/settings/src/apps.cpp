#include "apps.h"

#include "util.h"

#include <KApplicationTrader>
#include <KConfigGroup>
#include <KDesktopFile>
#include <KService>
#include <KSharedConfig>
#include <QCollator>
#include <QDir>
#include <QFileInfo>

struct Category {
    const char *id;
    const char *name;
    const char *icon;
    QStringList mimes;      // pierwsza decyduje o liście i bieżącym wyborze
};

static const QList<Category> &categories()
{
    static const QList<Category> list{
        {"browser", "Przeglądarka", "globe", {QStringLiteral("x-scheme-handler/https"), QStringLiteral("x-scheme-handler/http"), QStringLiteral("text/html"), QStringLiteral("application/xhtml+xml")}},
        {"mail", "Poczta", "mail", {QStringLiteral("x-scheme-handler/mailto")}},
        {"files", "Pliki", "folder", {QStringLiteral("inode/directory")}},
        {"terminal", "Terminal", "code", {}},
        {"text", "Edytor tekstu", "pencil", {QStringLiteral("text/plain")}},
        {"image", "Zdjęcia", "image", {QStringLiteral("image/jpeg"), QStringLiteral("image/png"), QStringLiteral("image/gif"), QStringLiteral("image/webp"), QStringLiteral("image/heif")}},
        {"music", "Muzyka", "music", {QStringLiteral("audio/mpeg"), QStringLiteral("audio/flac"), QStringLiteral("audio/ogg"), QStringLiteral("audio/x-wav"), QStringLiteral("audio/mp4")}},
        {"video", "Wideo", "video", {QStringLiteral("video/mp4"), QStringLiteral("video/x-matroska"), QStringLiteral("video/webm"), QStringLiteral("video/quicktime"), QStringLiteral("video/x-msvideo")}},
        {"pdf", "Dokumenty PDF", "doc", {QStringLiteral("application/pdf")}},
    };
    return list;
}

static QVariantMap appMap(const KService::Ptr &s)
{
    return {{QStringLiteral("id"), s->storageId()}, {QStringLiteral("name"), s->name()}, {QStringLiteral("icon"), s->icon()}};
}

Apps::Apps(QObject *parent)
    : QObject(parent)
    , m_preview(asterPreview())
{
    if (m_preview) {
        const auto app = [](const QString &id, const QString &name) { return QVariantMap{{QStringLiteral("id"), id}, {QStringLiteral("name"), name}, {QStringLiteral("icon"), QString()}}; };
        const auto cat = [](const char *id, const QVariantMap &current, const QVariantList &choices) {
            for (const Category &c : categories())
                if (qstrcmp(c.id, id) == 0)
                    return QVariantMap{{QStringLiteral("id"), QLatin1String(id)}, {QStringLiteral("name"), QString::fromUtf8(c.name)}, {QStringLiteral("icon"), QLatin1String(c.icon)},
                                       {QStringLiteral("current"), current.value(QStringLiteral("id"))}, {QStringLiteral("currentName"), current.value(QStringLiteral("name"))},
                                       {QStringLiteral("choices"), choices}};
            return QVariantMap();
        };
        const QVariantMap browser = app(QStringLiteral("org.aster.browser.desktop"), QStringLiteral("Przeglądarka")),
                          firefox = app(QStringLiteral("org.mozilla.firefox.desktop"), QStringLiteral("Firefox")),
                          files = app(QStringLiteral("org.aster.files.desktop"), QStringLiteral("Pliki")),
                          kate = app(QStringLiteral("org.kde.kate.desktop"), QStringLiteral("Kate")),
                          gwen = app(QStringLiteral("org.kde.gwenview.desktop"), QStringLiteral("Gwenview")),
                          okular = app(QStringLiteral("org.kde.okular.desktop"), QStringLiteral("Okular")),
                          elisa = app(QStringLiteral("org.kde.elisa.desktop"), QStringLiteral("Elisa")),
                          vlc = app(QStringLiteral("vlc.desktop"), QStringLiteral("VLC")),
                          konsole = app(QStringLiteral("org.kde.konsole.desktop"), QStringLiteral("Konsole")),
                          thunder = app(QStringLiteral("org.mozilla.Thunderbird.desktop"), QStringLiteral("Thunderbird"));
        m_categories = {cat("browser", browser, {browser, firefox}), cat("mail", thunder, {thunder, browser}), cat("files", files, {files}),
                        cat("terminal", konsole, {konsole}), cat("text", kate, {kate}), cat("image", gwen, {gwen, browser}),
                        cat("music", elisa, {elisa, vlc}), cat("video", vlc, {vlc}), cat("pdf", okular, {okular, browser})};
        m_autostart = {QVariantMap{{QStringLiteral("file"), QStringLiteral("a")}, {QStringLiteral("id"), QStringLiteral("discord")}, {QStringLiteral("name"), QStringLiteral("Discord")},
                                   {QStringLiteral("icon"), QString()}, {QStringLiteral("enabled"), true}},
                       QVariantMap{{QStringLiteral("file"), QStringLiteral("b")}, {QStringLiteral("id"), QStringLiteral("nextcloud")}, {QStringLiteral("name"), QStringLiteral("Nextcloud")},
                                   {QStringLiteral("icon"), QString()}, {QStringLiteral("enabled"), false}}};
        return;
    }
    refresh();
}

void Apps::refresh()
{
    if (m_preview)
        return;
    QVariantList list;
    for (const Category &c : categories()) {
        KService::List choices;
        KService::Ptr current;
        if (c.mimes.isEmpty()) {
            // Terminal: programy z kategorii TerminalEmulator; wybór w kdeglobals
            choices = KApplicationTrader::query([](const KService::Ptr &s) { return s->categories().contains(QLatin1String("TerminalEmulator")); });
            const QString id = KSharedConfig::openConfig(QStringLiteral("kdeglobals"))->group(QStringLiteral("General")).readEntry("TerminalService", QStringLiteral("org.kde.konsole.desktop"));
            current = KService::serviceByStorageId(id);
        } else {
            choices = KApplicationTrader::queryByMimeType(c.mimes.first());
            current = KApplicationTrader::preferredService(c.mimes.first());
        }
        QVariantList ch;
        QSet<QString> seen;
        for (const KService::Ptr &s : choices)
            if (!s->noDisplay() && !seen.contains(s->storageId())) {
                seen.insert(s->storageId());
                ch << appMap(s);
            }
        list << QVariantMap{{QStringLiteral("id"), QLatin1String(c.id)}, {QStringLiteral("name"), QString::fromUtf8(c.name)}, {QStringLiteral("icon"), QLatin1String(c.icon)},
                            {QStringLiteral("current"), current ? current->storageId() : QString()},
                            {QStringLiteral("currentName"), current ? current->name() : QStringLiteral("Brak")}, {QStringLiteral("choices"), ch}};
    }
    m_categories = list;
    readAutostart();
    Q_EMIT changed();
}

void Apps::setDefault(const QString &category, const QString &appId)
{
    for (QVariant &v : m_categories) {
        QVariantMap m = v.toMap();
        if (m.value(QStringLiteral("id")) != category)
            continue;
        m.insert(QStringLiteral("current"), appId);
        for (const QVariant &c : m.value(QStringLiteral("choices")).toList())
            if (c.toMap().value(QStringLiteral("id")) == appId)
                m.insert(QStringLiteral("currentName"), c.toMap().value(QStringLiteral("name")));
        v = m;
    }
    Q_EMIT changed();
    if (m_preview)
        return;
    const KService::Ptr service = KService::serviceByStorageId(appId);
    if (!service)
        return;
    for (const Category &c : categories()) {
        if (category != QLatin1String(c.id))
            continue;
        if (c.mimes.isEmpty()) {
            KConfigGroup g = KSharedConfig::openConfig(QStringLiteral("kdeglobals"))->group(QStringLiteral("General"));
            g.writeEntry("TerminalApplication", service->exec().section(QLatin1Char(' '), 0, 0), KConfig::Notify);
            g.writeEntry("TerminalService", appId, KConfig::Notify);
            g.sync();
        }
        for (const QString &mime : c.mimes)
            KApplicationTrader::setPreferredService(mime, service);
        if (category == QLatin1String("browser")) {
            KConfigGroup g = KSharedConfig::openConfig(QStringLiteral("kdeglobals"))->group(QStringLiteral("General"));
            g.writeEntry("BrowserApplication", appId, KConfig::Notify);
            g.sync();
        }
    }
}

// ——— Uruchamianie po zalogowaniu ———

static QString autostartDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/autostart");
}

void Apps::readAutostart()
{
    QVariantList list;
    const QDir dir(autostartDir());
    for (const QString &f : dir.entryList({QStringLiteral("*.desktop")}, QDir::Files, QDir::Name)) {
        const KDesktopFile df(dir.filePath(f));
        const KConfigGroup g = df.desktopGroup();
        if (g.readEntry("NoDisplay", false) && !g.readEntry("Hidden", false))
            continue;
        list << QVariantMap{{QStringLiteral("file"), dir.filePath(f)}, {QStringLiteral("id"), f}, {QStringLiteral("name"), df.readName()},
                            {QStringLiteral("icon"), df.readIcon()}, {QStringLiteral("enabled"), !g.readEntry("Hidden", false)}};
    }
    m_autostart = list;
}

QVariantList Apps::installed() const
{
    if (!m_installed.isEmpty() || m_preview)
        return m_installed;
    KService::List all = KApplicationTrader::query([](const KService::Ptr &s) { return !s->noDisplay() && !s->exec().isEmpty(); });
    QCollator c(QLocale(QStringLiteral("pl_PL")));
    std::sort(all.begin(), all.end(), [&c](const KService::Ptr &a, const KService::Ptr &b) { return c.compare(a->name(), b->name()) < 0; });
    for (const KService::Ptr &s : all)
        m_installed << appMap(s);
    return m_installed;
}

void Apps::addAutostart(const QString &appId)
{
    if (m_preview)
        return;
    const KService::Ptr s = KService::serviceByStorageId(appId);
    if (!s)
        return;
    QDir().mkpath(autostartDir());
    const QString target = autostartDir() + QLatin1Char('/') + QFileInfo(s->entryPath()).fileName();
    QFile::remove(target);
    QFile::copy(s->entryPath(), target);
    QFile(target).setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ReadGroup | QFile::ReadOther);
    readAutostart();
    Q_EMIT changed();
}

void Apps::setAutostartEnabled(const QString &file, bool on)
{
    if (m_preview || !file.startsWith(autostartDir()))
        return;
    KDesktopFile df(file);
    df.desktopGroup().writeEntry("Hidden", !on);
    df.sync();
    readAutostart();
    Q_EMIT changed();
}

void Apps::removeAutostart(const QString &file)
{
    if (m_preview || !file.startsWith(autostartDir()))
        return;
    QFile::remove(file);
    readAutostart();
    Q_EMIT changed();
}
