#include "webapps.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QPainter>
#include <QPainterPath>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>

#include <memory>

// Instalator przedstawia się uczciwie — gdy strona nie odpowiada automatom (np. WhatsApp),
// aplikacja i tak powstaje z nazwy domeny i ikony z usługi ikon stron
static const QByteArray agent = "Mozilla/5.0 (compatible; AsterWebApps/0.1; +https://aster.local)";

WebApps::WebApps(QObject *parent)
    : QObject(parent)
{
}

QString WebApps::dataDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/aster/webapps");
}

QString WebApps::appDir(const QString &id)
{
    return dataDir() + QLatin1Char('/') + id;
}

QVariantMap WebApps::load(const QString &id)
{
    QFile f(appDir(id) + QStringLiteral("/app.json"));
    if (!f.open(QIODevice::ReadOnly))
        return {};
    QVariantMap m = QJsonDocument::fromJson(f.readAll()).object().toVariantMap();
    m.insert(QStringLiteral("icon"), QUrl::fromLocalFile(appDir(id) + QStringLiteral("/icon.png")).toString());
    m.insert(QStringLiteral("profileDir"), appDir(id) + QStringLiteral("/profile"));
    return m;
}

QVariantList WebApps::installed() const
{
    QVariantList out;
    const QStringList ids = QDir(dataDir()).entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
    for (const QString &id : ids) {
        const QVariantMap m = load(id);
        if (!m.isEmpty())
            out << m;
    }
    return out;
}

void WebApps::setBusy(bool busy)
{
    if (busy != m_busy) {
        m_busy = busy;
        Q_EMIT busyChanged();
    }
}

void WebApps::fetch(const QUrl &url, Callback done)
{
    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::UserAgentHeader, agent);
    req.setRawHeader("Accept-Language", "pl-PL,pl;q=0.9,en;q=0.6");
    req.setTransferTimeout(12000);
    QNetworkReply *reply = m_net.get(req);
    connect(reply, &QNetworkReply::finished, this, [reply, done] {
        const bool ok = reply->error() == QNetworkReply::NoError;
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        done(ok ? reply->read(2 * 1024 * 1024) : QByteArray(), reply->url(), ok, status);
        reply->deleteLater();
    });
}

// Domena „bazowa”: mail.google.com → google.com, sklep.allegro.pl → allegro.pl, x.co.uk → x.co.uk
static QString baseDomain(const QString &host)
{
    const QStringList parts = host.split(QLatin1Char('.'), Qt::SkipEmptyParts);
    if (parts.size() <= 2)
        return host;
    static const QStringList second{QStringLiteral("co"), QStringLiteral("com"), QStringLiteral("org"), QStringLiteral("net"),
                                    QStringLiteral("gov"), QStringLiteral("edu"), QStringLiteral("ac")};
    const int n = parts.last().size() == 2 && second.contains(parts.at(parts.size() - 2)) ? 3 : 2;
    return parts.mid(parts.size() - n).join(QLatin1Char('.'));
}

// Atrybuty znacznika HTML: <link rel="icon" href="…" sizes="…">
static QHash<QString, QString> attributes(const QString &tag)
{
    static const QRegularExpression re(QStringLiteral("([a-zA-Z_:][-a-zA-Z0-9_:.]*)\\s*=\\s*(\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"));
    QHash<QString, QString> out;
    auto it = re.globalMatch(tag);
    while (it.hasNext()) {
        const auto m = it.next();
        const QString value = !m.captured(3).isNull() ? m.captured(3) : !m.captured(4).isNull() ? m.captured(4) : m.captured(5);
        out.insert(m.captured(1).toLower(), value.trimmed());
    }
    return out;
}

static int largestSize(const QString &sizes)
{
    int best = 0;
    for (const QString &s : sizes.split(QLatin1Char(' '), Qt::SkipEmptyParts))
        best = qMax(best, s.section(QLatin1Char('x'), 0, 0).toInt());
    return sizes.contains(QLatin1String("any")) ? 512 : best;
}

static QString cleanTitle(QString t)
{
    t = t.simplified();
    for (const QString sep : {QStringLiteral(" | "), QStringLiteral(" - "), QStringLiteral(" – "), QStringLiteral(" — "), QStringLiteral(": ")}) {
        const int i = t.indexOf(sep);
        if (i >= 3)
            t = t.left(i);
    }
    return t.left(32);
}

void WebApps::inspect(const QString &text)
{
    QUrl url = QUrl::fromUserInput(text.trimmed());
    if (!url.isValid() || url.host().isEmpty()) {
        Q_EMIT failed(QStringLiteral("To nie wygląda na adres strony."));
        return;
    }
    if (url.scheme() == QLatin1String("http"))
        url.setScheme(QStringLiteral("https"));
    setBusy(true);

    fetch(url, [this, url](const QByteArray &data, const QUrl &finalUrl, bool ok, int status) {
        // Strona odpowiedziała, ale nie chce rozmawiać z automatem — dalej bez jej HTML
        if (!ok && status >= 400)
            ok = true;
        if (!ok) {
            setBusy(false);
            Q_EMIT failed(QStringLiteral("Nie udało się otworzyć %1. Sprawdź adres i połączenie z internetem.").arg(url.host()));
            return;
        }
        const QString html = QString::fromUtf8(data);
        auto info = std::make_shared<QVariantMap>();
        (*info)[QStringLiteral("url")] = finalUrl.toString();
        (*info)[QStringLiteral("host")] = finalUrl.host();
        (*info)[QStringLiteral("scope")] = baseDomain(finalUrl.host());
        (*info)[QStringLiteral("backgroundColor")] = QStringLiteral("#FFFFFF");

        static const QRegularExpression titleRe(QStringLiteral("<title[^>]*>([^<]*)</title>"), QRegularExpression::CaseInsensitiveOption);
        const QString title = cleanTitle(titleRe.match(html).captured(1));
        QString fromHost = baseDomain(finalUrl.host()).section(QLatin1Char('.'), 0, 0);
        if (!fromHost.isEmpty())
            fromHost[0] = fromHost.at(0).toUpper();
        // Nazwa: tytuł strony tylko, gdy jest krótki (inaczej „Notion”, nie „The AI workspace that…”);
        // metadane aplikacji niżej mają pierwszeństwo
        (*info)[QStringLiteral("name")] = !title.isEmpty() && title.size() <= 20 ? title : fromHost;
        QString metaName;

        // Ikony: [„M”|„F”|„A”] + adres — M: maskable, F: pełna (apple-touch-icon), A: zwykła
        auto icons = std::make_shared<QList<QPair<int, QString>>>();
        QUrl manifestUrl;
        static const QRegularExpression tagRe(QStringLiteral("<(link|meta)\\b[^>]*>"), QRegularExpression::CaseInsensitiveOption);
        auto it = tagRe.globalMatch(html);
        while (it.hasNext()) {
            const QString tag = it.next().captured(0);
            const auto a = attributes(tag);
            const QString rel = a.value(QStringLiteral("rel")).toLower();
            if (tag.startsWith(QLatin1String("<meta"), Qt::CaseInsensitive)) {
                const QString metaKey = (a.value(QStringLiteral("name")) + a.value(QStringLiteral("property"))).toLower();
                if (metaKey == QLatin1String("theme-color") && !a.value(QStringLiteral("media")).contains(QLatin1String("dark")))
                    (*info)[QStringLiteral("themeColor")] = a.value(QStringLiteral("content"));
                else if ((metaKey == QLatin1String("apple-mobile-web-app-title") || metaKey == QLatin1String("application-name")
                          || (metaKey == QLatin1String("og:site_name") && metaName.isEmpty()))
                         && !a.value(QStringLiteral("content")).trimmed().isEmpty() && a.value(QStringLiteral("content")).size() <= 24)
                    metaName = a.value(QStringLiteral("content")).trimmed();
                continue;
            }
            const QString href = finalUrl.resolved(QUrl(a.value(QStringLiteral("href")))).toString();
            if (rel == QLatin1String("manifest"))
                manifestUrl = QUrl(href);
            else if (rel.contains(QLatin1String("apple-touch-icon")))
                icons->append({1000 + largestSize(a.value(QStringLiteral("sizes"), QStringLiteral("180x180"))), QStringLiteral("F|") + href});
            else if (rel.split(QLatin1Char(' ')).contains(QLatin1String("icon")))
                icons->append({largestSize(a.value(QStringLiteral("sizes"))), QStringLiteral("A|") + href});
        }

        if (!metaName.isEmpty())
            (*info)[QStringLiteral("name")] = metaName;

        auto finish = [this, info, icons, finalUrl] {
            QList<QPair<int, QString>> list = *icons;
            std::sort(list.begin(), list.end(), [](const auto &a, const auto &b) { return a.first > b.first; });
            QStringList candidates;
            for (const auto &p : list)
                candidates << p.second;
            candidates << QStringLiteral("A|https://www.google.com/s2/favicons?sz=256&domain=") + finalUrl.host();
            if (baseDomain(finalUrl.host()) != finalUrl.host())
                candidates << QStringLiteral("A|https://www.google.com/s2/favicons?sz=256&domain=") + baseDomain(finalUrl.host());
            tryIcons(candidates, [this, info](const QImage &img, bool maskable) {
                const QColor bg((*info).value(QStringLiteral("backgroundColor")).toString());
                QImage tile;
                if (!img.isNull())
                    tile = composeIcon(img, maskable, bg.isValid() ? bg : QColor(Qt::white));
                const QString path = QStandardPaths::writableLocation(QStandardPaths::TempLocation) + QStringLiteral("/aster-webapp-")
                    + QString::fromLatin1(QCryptographicHash::hash((*info).value(QStringLiteral("url")).toByteArray(), QCryptographicHash::Md5).toHex().left(10))
                    + QStringLiteral(".png");
                if (!tile.isNull() && tile.save(path))
                    (*info)[QStringLiteral("icon")] = QUrl::fromLocalFile(path).toString();
                setBusy(false);
                Q_EMIT inspected(*info);
            });
        };

        if (!manifestUrl.isValid()) {
            finish();
            return;
        }
        fetch(manifestUrl, [info, icons, finish, manifestUrl, finalUrl](const QByteArray &mdata, const QUrl &, bool mok, int) {
            const QJsonObject m = mok ? QJsonDocument::fromJson(mdata).object() : QJsonObject();
            if (!m.isEmpty()) {
                const QString shortName = m.value(QStringLiteral("short_name")).toString();
                const QString name = m.value(QStringLiteral("name")).toString();
                const QString pick = !shortName.isEmpty() && (shortName.size() <= 16 || name.isEmpty()) ? shortName : name;
                if (!pick.isEmpty())
                    (*info)[QStringLiteral("name")] = pick.left(32);
                if (m.contains(QStringLiteral("theme_color")))
                    (*info)[QStringLiteral("themeColor")] = m.value(QStringLiteral("theme_color")).toString();
                if (m.contains(QStringLiteral("background_color")))
                    (*info)[QStringLiteral("backgroundColor")] = m.value(QStringLiteral("background_color")).toString();
                const QString start = m.value(QStringLiteral("start_url")).toString();
                if (!start.isEmpty()) {
                    const QUrl s = manifestUrl.resolved(QUrl(start));
                    if (baseDomain(s.host()) == baseDomain(finalUrl.host()))
                        (*info)[QStringLiteral("url")] = s.toString();
                }
                for (const QJsonValue &v : m.value(QStringLiteral("icons")).toArray()) {
                    const QJsonObject ic = v.toObject();
                    const QString src = manifestUrl.resolved(QUrl(ic.value(QStringLiteral("src")).toString())).toString();
                    const bool maskable = ic.value(QStringLiteral("purpose")).toString().contains(QLatin1String("maskable"));
                    const int size = largestSize(ic.value(QStringLiteral("sizes")).toString());
                    if (size >= 96 || size == 0)
                        icons->append({(maskable ? 3000 : 2000) + qMin(size, 512), (maskable ? QStringLiteral("M|") : QStringLiteral("A|")) + src});
                }
            }
            finish();
        });
    });
}

void WebApps::tryIcons(QStringList candidates, std::function<void(const QImage &, bool)> done)
{
    if (candidates.isEmpty()) {
        done({}, false);
        return;
    }
    const QString c = candidates.takeFirst();
    const QChar kind = c.at(0);
    fetch(QUrl(c.mid(2)), [this, candidates, done, kind](const QByteArray &data, const QUrl &, bool ok, int) {
        const QImage img = ok ? QImage::fromData(data) : QImage();
        if (img.isNull() || img.width() < 32) {
            tryIcons(candidates, done);
            return;
        }
        done(img, kind == QLatin1Char('M') || kind == QLatin1Char('F'));
    });
}

QImage composeIcon(const QImage &srcIn, bool maskable, const QColor &background)
{
    const int S = 256;
    const qreal radius = S * 0.225;
    QImage out(S, S, QImage::Format_ARGB32_Premultiplied);
    out.fill(Qt::transparent);
    QPainter p(&out);
    p.setRenderHints(QPainter::Antialiasing | QPainter::SmoothPixmapTransform);
    QPainterPath tile;
    tile.addRoundedRect(QRectF(0, 0, S, S), radius, radius);

    const QImage src = srcIn.convertToFormat(QImage::Format_ARGB32);
    const int w = src.width() - 1, h = src.height() - 1;
    const bool opaqueCorners = qAlpha(src.pixel(1, 1)) > 245 && qAlpha(src.pixel(w - 1, 1)) > 245
                            && qAlpha(src.pixel(1, h - 1)) > 245 && qAlpha(src.pixel(w - 1, h - 1)) > 245;
    p.setClipPath(tile);
    if (maskable || opaqueCorners) {
        const QImage scaled = src.scaled(S, S, Qt::KeepAspectRatioByExpanding, Qt::SmoothTransformation);
        p.drawImage(QPointF((S - scaled.width()) / 2.0, (S - scaled.height()) / 2.0), scaled);
    } else {
        p.fillPath(tile, background.isValid() ? background : QColor(Qt::white));
        const QImage scaled = src.scaled(int(S * 0.62), int(S * 0.62), Qt::KeepAspectRatio, Qt::SmoothTransformation);
        p.drawImage(QPointF((S - scaled.width()) / 2.0, (S - scaled.height()) / 2.0), scaled);
    }
    // Delikatna obwódka — kafelek nie zlewa się z jasnym tłem
    p.setClipping(false);
    p.setPen(QPen(QColor(0, 0, 0, 26), 2));
    QPainterPath edge;
    edge.addRoundedRect(QRectF(1, 1, S - 2, S - 2), radius - 1, radius - 1);
    p.drawPath(edge);
    return out;
}

// Litera na kolorowym kafelku — gdy strona nie ma żadnej ikony
static QImage letterIcon(const QString &name, const QColor &color)
{
    const int S = 256;
    QImage out(S, S, QImage::Format_ARGB32_Premultiplied);
    out.fill(Qt::transparent);
    QPainter p(&out);
    p.setRenderHints(QPainter::Antialiasing | QPainter::TextAntialiasing);
    QPainterPath tile;
    tile.addRoundedRect(QRectF(0, 0, S, S), S * 0.225, S * 0.225);
    p.fillPath(tile, color.isValid() ? color : QColor(0x34, 0x56, 0xE8));
    QFont f(QStringLiteral("Outfit"));
    f.setPixelSize(132);
    f.setWeight(QFont::DemiBold);
    p.setFont(f);
    p.setPen(Qt::white);
    p.drawText(QRect(0, 0, S, S), Qt::AlignCenter, name.left(1).toUpper());
    return out;
}

static QString slug(const QString &name)
{
    QString s = name.toLower();
    const QString from = QStringLiteral("ąćęłńóśźż");
    const QString to = QStringLiteral("acelnoszz");
    for (int i = 0; i < from.size(); ++i)
        s.replace(from.at(i), to.at(i));
    s.replace(QRegularExpression(QStringLiteral("[^a-z0-9]+")), QStringLiteral("-"));
    s = s.mid(s.startsWith(QLatin1Char('-')) ? 1 : 0);
    if (s.endsWith(QLatin1Char('-')))
        s.chop(1);
    return s.isEmpty() ? QStringLiteral("aplikacja") : s.left(40);
}

static QString desktopPath(const QString &id)
{
    return QStandardPaths::writableLocation(QStandardPaths::ApplicationsLocation) + QStringLiteral("/aster-webapp-") + id + QStringLiteral(".desktop");
}

static void refreshMenus()
{
    QProcess::startDetached(QStringLiteral("kbuildsycoca6"), {});
}

void WebApps::install(const QVariantMap &info)
{
    const QString name = info.value(QStringLiteral("name")).toString().trimmed();
    const QString url = info.value(QStringLiteral("url")).toString();
    if (name.isEmpty() || url.isEmpty()) {
        Q_EMIT failed(QStringLiteral("Brakuje nazwy albo adresu."));
        return;
    }
    // Ta sama strona zainstalowana drugi raz → nadpisz; inna o tej samej nazwie → dopisz numer
    QString id = idForUrl(url);
    if (id.isEmpty()) {
        id = slug(name);
        for (int i = 2; QDir(appDir(id)).exists(); ++i)
            id = slug(name) + QLatin1Char('-') + QString::number(i);
    }
    const QString dir = appDir(id);
    QDir().mkpath(dir);

    const QString iconPath = dir + QStringLiteral("/icon.png");
    const QImage icon(QUrl(info.value(QStringLiteral("icon")).toString()).toLocalFile());
    (icon.isNull() ? letterIcon(name, QColor(info.value(QStringLiteral("themeColor")).toString())) : icon).save(iconPath);

    const QString category = info.value(QStringLiteral("category"), QStringLiteral("internet")).toString();
    QJsonObject app{
        {QStringLiteral("id"), id},
        {QStringLiteral("name"), name},
        {QStringLiteral("url"), url},
        {QStringLiteral("host"), QUrl(url).host()},
        {QStringLiteral("scope"), info.value(QStringLiteral("scope"), baseDomain(QUrl(url).host())).toString()},
        {QStringLiteral("themeColor"), info.value(QStringLiteral("themeColor")).toString()},
        {QStringLiteral("backgroundColor"), info.value(QStringLiteral("backgroundColor"), QStringLiteral("#FFFFFF")).toString()},
        {QStringLiteral("category"), category},
    };
    QSaveFile json(dir + QStringLiteral("/app.json"));
    if (!json.open(QIODevice::WriteOnly)) {
        Q_EMIT failed(QStringLiteral("Nie udało się zapisać aplikacji."));
        return;
    }
    json.write(QJsonDocument(app).toJson());
    json.commit();

    static const QHash<QString, QString> categories{
        {QStringLiteral("internet"), QStringLiteral("Network;")},
        {QStringLiteral("biuro"), QStringLiteral("Office;")},
        {QStringLiteral("multimedia"), QStringLiteral("AudioVideo;")},
        {QStringLiteral("grafika"), QStringLiteral("Graphics;")},
        {QStringLiteral("gry"), QStringLiteral("Game;")},
        {QStringLiteral("edukacja"), QStringLiteral("Education;")},
        {QStringLiteral("programowanie"), QStringLiteral("Development;")},
        {QStringLiteral("narzedzia"), QStringLiteral("Utility;")},
    };
    QDir().mkpath(QFileInfo(desktopPath(id)).path());
    QSaveFile desktop(desktopPath(id));
    if (desktop.open(QIODevice::WriteOnly)) {
        const QString text = QStringLiteral(
            "[Desktop Entry]\nType=Application\nName=%1\nComment=Aplikacja webowa — %2\nExec=\"%3\" --run %4\nIcon=%5\n"
            "Terminal=false\nCategories=%6\nStartupWMClass=aster-webapp-%4\nX-Aster-WebApp=%4\n")
            .arg(name, QUrl(url).host(), QCoreApplication::applicationFilePath(), id, iconPath,
                 categories.value(category, QStringLiteral("Network;")));
        desktop.write(text.toUtf8());
        desktop.commit();
    }
    refreshMenus();
    Q_EMIT installedChanged();
    Q_EMIT installedApp(id);
}

void WebApps::uninstall(const QString &id)
{
    if (id.isEmpty() || id.contains(QLatin1Char('/')))
        return;
    QFile::remove(desktopPath(id));
    QDir(appDir(id)).removeRecursively();
    refreshMenus();
    Q_EMIT installedChanged();
}

void WebApps::launch(const QString &id)
{
    QProcess::startDetached(QCoreApplication::applicationFilePath(), {QStringLiteral("--run"), id});
}

QString WebApps::idForUrl(const QString &url) const
{
    const QString host = QUrl::fromUserInput(url).host();
    for (const QVariant &v : installed()) {
        const QVariantMap m = v.toMap();
        if (m.value(QStringLiteral("host")).toString() == host)
            return m.value(QStringLiteral("id")).toString();
    }
    return {};
}

bool WebApps::isInstalledUrl(const QString &url) const
{
    return !idForUrl(url).isEmpty();
}
