#include "share.h"

#include <QBuffer>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusVariant>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFont>
#include <QLinearGradient>
#include <QPainter>
#include <QPainterPath>
#include <QUrl>
#include <QVariantMap>
#include <archive.h>
#include <archive_entry.h>
#include <taglib/attachedpictureframe.h>
#include <taglib/id3v2tag.h>
#include <taglib/mpegfile.h>
#include <taglib/textidentificationframe.h>

namespace Share {

QImage cover(const QString &title, const QString &artist, const std::vector<float> &wave)
{
    // Kolory: para z palety wybrana po tytule — ta sama piosenka ma zawsze tę samą okładkę
    static const char *pairs[][2] = {{"#8E5CFF", "#2A0F6B"}, {"#FF6B6B", "#6B0F2A"}, {"#22B8CF", "#0B3A6B"},
                                     {"#F5B83D", "#9A2D0B"}, {"#51CF66", "#0B4A3A"}, {"#F06595", "#3A0B5C"}};
    const size_t pick = qHash(title) % (sizeof pairs / sizeof pairs[0]);
    const int S = 1200;
    QImage img(S, S, QImage::Format_RGB32);
    QPainter p(&img);
    p.setRenderHint(QPainter::Antialiasing);
    QLinearGradient g(0, 0, S, S);
    g.setColorAt(0, QColor(QString::fromLatin1(pairs[pick][0])));
    g.setColorAt(1, QColor(QString::fromLatin1(pairs[pick][1])));
    p.fillRect(img.rect(), g);
    // Poświata
    QRadialGradient glow(S * 0.75, S * 0.2, S * 0.7);
    glow.setColorAt(0, QColor(255, 255, 255, 70));
    glow.setColorAt(1, QColor(255, 255, 255, 0));
    p.fillRect(img.rect(), glow);

    // Kształt fali: słupki odbite względem środka
    const int bars = 72, left = 90, width = S - 180;
    const double bw = double(width) / bars;
    for (int i = 0; i < bars; ++i) {
        float v = 0.08f;
        if (!wave.empty()) {
            const size_t a = size_t(double(i) / bars * wave.size()), b = std::max(a + 1, size_t(double(i + 1) / bars * wave.size()));
            for (size_t k = a; k < b && k < wave.size(); ++k)
                v = std::max(v, wave[k]);
        }
        const double h = std::min(1.0, double(v) * 1.15) * S * 0.30;
        QPainterPath bar;
        bar.addRoundedRect(QRectF(left + i * bw + bw * 0.2, S * 0.42 - h / 2, bw * 0.6, std::max(8.0, h)), bw * 0.3, bw * 0.3);
        p.fillPath(bar, QColor(255, 255, 255, 215));
    }

    // Tytuł i wykonawca
    QFont f(QStringLiteral("Geist"));
    f.setPixelSize(104);
    f.setWeight(QFont::Bold);
    p.setFont(f);
    p.setPen(Qt::white);
    const QRect titleRect(90, int(S * 0.70), S - 180, 230);
    p.drawText(titleRect, Qt::AlignLeft | Qt::AlignTop | Qt::TextWordWrap, title);
    f.setPixelSize(52);
    f.setWeight(QFont::Medium);
    p.setFont(f);
    p.setPen(QColor(255, 255, 255, 210));
    p.drawText(QRect(90, S - 150, S - 180, 70), Qt::AlignLeft | Qt::AlignVCenter, artist);
    f.setPixelSize(30);
    f.setWeight(QFont::DemiBold);
    f.setLetterSpacing(QFont::AbsoluteSpacing, 3);
    p.setFont(f);
    p.setPen(QColor(255, 255, 255, 150));
    p.drawText(QRect(90, 80, S - 180, 50), Qt::AlignLeft | Qt::AlignVCenter, QStringLiteral("STUDIO ASTER"));
    return img;
}

bool tagMp3(const QString &path, const QString &title, const QString &artist, const QImage &cover)
{
    TagLib::MPEG::File file(QFile::encodeName(path).constData());
    if (!file.isValid())
        return false;
    TagLib::ID3v2::Tag *tag = file.ID3v2Tag(true);
    tag->setTitle(TagLib::String(title.toStdString(), TagLib::String::UTF8));
    tag->setArtist(TagLib::String(artist.toStdString(), TagLib::String::UTF8));
    tag->setAlbum(TagLib::String("Studio Aster", TagLib::String::UTF8));
    if (!cover.isNull()) {
        QByteArray jpeg;
        QBuffer buf(&jpeg);
        buf.open(QIODevice::WriteOnly);
        cover.scaled(800, 800, Qt::KeepAspectRatio, Qt::SmoothTransformation).save(&buf, "JPEG", 88);
        auto *pic = new TagLib::ID3v2::AttachedPictureFrame;
        pic->setMimeType("image/jpeg");
        pic->setType(TagLib::ID3v2::AttachedPictureFrame::FrontCover);
        pic->setPicture(TagLib::ByteVector(jpeg.constData(), uint(jpeg.size())));
        tag->removeFrames("APIC");
        tag->addFrame(pic);
    }
    return file.save(TagLib::MPEG::File::ID3v2);
}

bool packProject(const QString &folder, const QStringList &files, const QString &zipPath, QString *error)
{
    archive *a = archive_write_new();
    archive_write_set_format_zip(a);
    if (archive_write_open_filename(a, QFile::encodeName(zipPath).constData()) != ARCHIVE_OK) {
        if (error)
            *error = QString::fromUtf8(archive_error_string(a));
        archive_write_free(a);
        return false;
    }
    const QString root = QFileInfo(folder).fileName();
    bool ok = true;
    for (const QString &rel : files) {
        QFile f(folder + QLatin1Char('/') + rel);
        if (!f.open(QIODevice::ReadOnly))
            continue;
        archive_entry *e = archive_entry_new();
        archive_entry_set_pathname_utf8(e, (root + QLatin1Char('/') + rel).toUtf8().constData());
        archive_entry_set_size(e, f.size());
        archive_entry_set_filetype(e, AE_IFREG);
        archive_entry_set_perm(e, 0644);
        archive_entry_set_mtime(e, QFileInfo(f).lastModified().toSecsSinceEpoch(), 0);
        archive_write_header(a, e);
        while (!f.atEnd()) {
            const QByteArray chunk = f.read(1 << 20);
            if (archive_write_data(a, chunk.constData(), size_t(chunk.size())) < 0) {
                ok = false;
                break;
            }
        }
        archive_entry_free(e);
        if (!ok)
            break;
    }
    if (!ok && error)
        *error = QString::fromUtf8(archive_error_string(a));
    archive_write_close(a);
    archive_write_free(a);
    if (!ok)
        QFile::remove(zipPath);
    return ok;
}

QString unpackProject(const QString &zipPath, const QString &projectsFolder, QString *error)
{
    archive *a = archive_read_new();
    archive_read_support_format_zip(a);
    if (archive_read_open_filename(a, QFile::encodeName(zipPath).constData(), 1 << 16) != ARCHIVE_OK) {
        if (error)
            *error = QStringLiteral("To nie jest paczka projektu.");
        archive_read_free(a);
        return {};
    }
    // Nazwa: pierwszy katalog w paczce; jeśli taki projekt już jest — „(remiks)”
    QString target;
    archive_entry *e;
    bool sawProject = false;
    while (archive_read_next_header(a, &e) == ARCHIVE_OK) {
        QString name = QString::fromUtf8(archive_entry_pathname_utf8(e) ? archive_entry_pathname_utf8(e) : archive_entry_pathname(e));
        name = QDir::cleanPath(name);
        const QStringList parts = name.split(QLatin1Char('/'), Qt::SkipEmptyParts);
        // Bezpieczeństwo: bez ścieżek bezwzględnych i „..”, tylko zwykłe pliki
        if (parts.size() < 2 || name.startsWith(QLatin1Char('/')) || parts.contains(QStringLiteral(".."))
            || archive_entry_filetype(e) != AE_IFREG) {
            archive_read_data_skip(a);
            continue;
        }
        if (target.isEmpty()) {
            QString base = projectsFolder + QLatin1Char('/') + parts.first();
            target = base;
            if (QFileInfo::exists(target))
                target = base + QStringLiteral(" (remiks)");
            for (int i = 2; QFileInfo::exists(target); ++i)
                target = base + QStringLiteral(" (remiks %1)").arg(i);
        }
        const QString rel = parts.mid(1).join(QLatin1Char('/'));
        if (rel == QLatin1String("projekt.json"))
            sawProject = true;
        const QString out = target + QLatin1Char('/') + rel;
        QDir().mkpath(QFileInfo(out).absolutePath());
        QFile f(out);
        if (!f.open(QIODevice::WriteOnly)) {
            archive_read_data_skip(a);
            continue;
        }
        char buf[1 << 16];
        la_ssize_t n;
        while ((n = archive_read_data(a, buf, sizeof buf)) > 0)
            f.write(buf, n);
    }
    archive_read_free(a);
    if (!sawProject) {
        if (error)
            *error = QStringLiteral("W paczce nie ma projektu Studia.");
        if (!target.isEmpty() && target.startsWith(projectsFolder + QLatin1Char('/')))
            QDir(target).removeRecursively();
        return {};
    }
    return target;
}

namespace {
const QString service = QStringLiteral("org.kde.kdeconnect");
const QString daemonPath = QStringLiteral("/modules/kdeconnect");

QVariant call(const QString &path, const QString &iface, const QString &method, const QVariantList &args = {})
{
    QDBusMessage msg = QDBusMessage::createMethodCall(service, path, iface, method);
    msg.setArguments(args);
    const QDBusMessage reply = QDBusConnection::sessionBus().call(msg, QDBus::Block, 3000);
    if (reply.type() != QDBusMessage::ReplyMessage)
        return {};
    return reply.arguments().isEmpty() ? QVariant(true) : reply.arguments().constFirst();
}
}

QVariantList phones()
{
    QVariantList list;
    const QStringList ids = call(daemonPath, QStringLiteral("org.kde.kdeconnect.daemon"), QStringLiteral("devices"), {true, true}).toStringList();
    for (const QString &id : ids) {
        QDBusMessage msg = QDBusMessage::createMethodCall(service, daemonPath + QStringLiteral("/devices/") + id,
                                                          QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"));
        msg << QStringLiteral("org.kde.kdeconnect.device") << QStringLiteral("name");
        const QDBusMessage reply = QDBusConnection::sessionBus().call(msg, QDBus::Block, 2000);
        const QString name = reply.arguments().isEmpty() ? id : reply.arguments().constFirst().value<QDBusVariant>().variant().toString();
        list.append(QVariantMap{{QStringLiteral("id"), id}, {QStringLiteral("name"), name}});
    }
    return list;
}

bool sendToPhone(const QString &id, const QString &path)
{
    return call(daemonPath + QStringLiteral("/devices/") + id + QStringLiteral("/share"), QStringLiteral("org.kde.kdeconnect.device.share"),
                QStringLiteral("shareUrls"), {QStringList{QUrl::fromLocalFile(path).toString()}}).isValid();
}

} // namespace Share
