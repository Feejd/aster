#include "library.h"
#include "online.h"

#include "art.h"

#include <QCollator>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QFontDatabase>
#include <QJsonDocument>
#include <QLocale>
#include <QSettings>
#include <QStandardPaths>
#include <QUrl>
#include <algorithm>
#include <private/qzipreader_p.h>

Library::Library(QObject *parent)
    : QObject(parent)
{
    // Szablony wbudowane w program (apps/grafika/templates), kolejność według nazw plików
    QDir dir(QStringLiteral(":/szablony"));
    const QStringList files = dir.entryList({QStringLiteral("*.json")}, QDir::Files, QDir::Name);
    for (const QString &f : files) {
        QFile file(dir.filePath(f));
        if (!file.open(QIODevice::ReadOnly))
            continue;
        const QVariantMap doc = QJsonDocument::fromJson(file.readAll()).toVariant().toMap();
        m_templates.append(QVariantMap{
            {QStringLiteral("file"), dir.filePath(f)},
            {QStringLiteral("name"), doc.value(QStringLiteral("name"))},
            {QStringLiteral("category"), doc.value(QStringLiteral("category"))},
            {QStringLiteral("width"), doc.value(QStringLiteral("width"))},
            {QStringLiteral("height"), doc.value(QStringLiteral("height"))},
            {QStringLiteral("pages"), qMax(1, int(doc.value(QStringLiteral("pages")).toList().size()))},
        });
    }
    refresh();
}

QString Library::projectsFolder() const
{
    return QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation) + QStringLiteral("/Grafiki");
}

QStringList Library::fonts() const
{
    QStringList out;
    const QStringList families = QFontDatabase::families(QFontDatabase::Latin);
    for (const QString &f : families) {
        if (QFontDatabase::isPrivateFamily(f) || Online::previewOnly(f) || f.contains(QLatin1String("Emoji")) || f.contains(QLatin1String("Symbol"))
            || f.startsWith(QLatin1String("Droid Sans ")) || f.contains(QLatin1String("Dingbat")) || f == QLatin1String("D050000L"))
            continue;
        out.append(f);
    }
    QCollator c;
    c.setCaseSensitivity(Qt::CaseInsensitive);
    std::sort(out.begin(), out.end(), [&c](const QString &a, const QString &b) { return c.compare(a, b) < 0; });
    return out;
}

static QString when(const QDateTime &t)
{
    const QDate d = t.date(), today = QDate::currentDate();
    if (d == today)
        return QStringLiteral("Dziś, ") + QLocale().toString(t.time(), QStringLiteral("HH:mm"));
    if (d == today.addDays(-1))
        return QStringLiteral("Wczoraj, ") + QLocale().toString(t.time(), QStringLiteral("HH:mm"));
    return QLocale(QLocale::Polish).toString(d, d.year() == today.year() ? QStringLiteral("d MMMM") : QStringLiteral("d MMMM yyyy"));
}

void Library::refresh()
{
    QSettings s;
    QStringList paths = s.value(QStringLiteral("recent")).toStringList();
    QDir dir(projectsFolder());
    for (const QFileInfo &fi : dir.entryInfoList({QStringLiteral("*.grafika")}, QDir::Files))
        if (!paths.contains(fi.absoluteFilePath()))
            paths.append(fi.absoluteFilePath());
    QList<QFileInfo> infos;
    for (const QString &p : std::as_const(paths)) {
        QFileInfo fi(p);
        if (fi.exists())
            infos.append(fi);
    }
    std::sort(infos.begin(), infos.end(), [](const QFileInfo &a, const QFileInfo &b) { return a.lastModified() > b.lastModified(); });
    m_projects.clear();
    for (const QFileInfo &fi : std::as_const(infos))
        m_projects.append(QVariantMap{
            {QStringLiteral("path"), fi.absoluteFilePath()},
            {QStringLiteral("name"), fi.completeBaseName()},
            {QStringLiteral("when"), when(fi.lastModified())},
            {QStringLiteral("stamp"), fi.lastModified().toSecsSinceEpoch()},
        });
    Q_EMIT projectsChanged();
}

void Library::addRecent(const QString &path)
{
    if (path.isEmpty())
        return;
    QSettings s;
    QStringList list = s.value(QStringLiteral("recent")).toStringList();
    list.removeAll(path);
    list.prepend(path);
    while (list.size() > 40)
        list.removeLast();
    s.setValue(QStringLiteral("recent"), list);
    refresh();
}

bool Library::trash(const QString &path)
{
    const bool ok = QFile::moveToTrash(path);
    refresh();
    return ok;
}

QVariantList Library::photos() const
{
    struct Photo { QString path; QDateTime time; };
    QList<Photo> found;
    const QString root = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation);
    QDirIterator it(root, {QStringLiteral("*.jpg"), QStringLiteral("*.jpeg"), QStringLiteral("*.png"), QStringLiteral("*.webp"),
                           QStringLiteral("*.JPG"), QStringLiteral("*.JPEG"), QStringLiteral("*.PNG")},
                    QDir::Files, QDirIterator::Subdirectories);
    int scanned = 0;
    while (it.hasNext() && scanned < 4000) {
        const QFileInfo fi = it.nextFileInfo();
        ++scanned;
        // Pomijamy własne eksporty programu i ukryte foldery
        if (fi.absolutePath().contains(QLatin1String("/.")) || fi.absolutePath() == root + QStringLiteral("/Grafiki"))
            continue;
        found.append({fi.absoluteFilePath(), fi.lastModified()});
    }
    std::sort(found.begin(), found.end(), [](const Photo &a, const Photo &b) { return a.time > b.time; });
    QVariantList out;
    for (int i = 0; i < found.size() && i < 60; ++i)
        out.append(QUrl::fromLocalFile(found.at(i).path).toString());
    return out;
}

void Library::open(const QString &path) const
{
    QDesktopServices::openUrl(QUrl::fromLocalFile(path));
}

void Library::showInFolder(const QString &path) const
{
    QDBusMessage msg = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.FileManager1"),
                                                      QStringLiteral("/org/freedesktop/FileManager1"),
                                                      QStringLiteral("org.freedesktop.FileManager1"),
                                                      QStringLiteral("ShowItems"));
    msg << QStringList{QUrl::fromLocalFile(path).toString()} << QString();
    QDBusConnection::sessionBus().asyncCall(msg);
}

QString Library::toPath(const QString &url) const
{
    return url.startsWith(QLatin1String("file:")) ? QUrl(url).toLocalFile() : url;
}

// ——— Miniatury ———

ThumbProvider::ThumbProvider()
    : QQuickImageProvider(QQuickImageProvider::Image)
{
}

QImage ThumbProvider::requestImage(const QString &rawId, QSize *size, const QSize &requestedSize)
{
    QString id = QUrl::fromPercentEncoding(rawId.toUtf8());
    const int q = id.lastIndexOf(QLatin1Char('?'));   // ?<znacznik czasu> — tylko po to, żeby odświeżyć miniaturę
    if (q > 0)
        id.truncate(q);
    const int side = qMax(64, qMax(requestedSize.width(), requestedSize.height()));
    QImage img;
    if (id.startsWith(QLatin1String("t/"))) {
        QFile f(id.mid(2));
        if (f.open(QIODevice::ReadOnly)) {
            const QVariantMap doc = QJsonDocument::fromJson(f.readAll()).toVariant().toMap();
            const qreal w = doc.value(QStringLiteral("width")).toDouble(), h = doc.value(QStringLiteral("height")).toDouble();
            if (w > 0 && h > 0) {
                const qreal k = side / qMax(w, h);
                img = Art::renderPage(doc, QSize(qMax(1, qRound(w * k)), qMax(1, qRound(h * k))), nullptr);
            }
        }
    } else if (id.startsWith(QLatin1String("p/"))) {
        QZipReader zip(id.mid(2));
        img.loadFromData(zip.fileData(QStringLiteral("thumbnail.png")));
        if (!img.isNull() && qMax(img.width(), img.height()) > side)
            img = img.scaled(side, side, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    }
    if (size)
        *size = img.size();
    return img;
}
