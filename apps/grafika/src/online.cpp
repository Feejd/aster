#include "online.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QFontDatabase>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMap>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QPointer>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>
#include <QUrlQuery>

namespace {

const char *UserAgent = "AsterPixel/1.0 (+https://github.com/Feejd/aster)";

// Zestawy z Iconify na licencjach bez obowiązku podpisu
const char *IconSets = "tabler,lucide,ph,mdi,material-symbols,mingcute,ri,iconoir,heroicons,fluent";
const char *StickerSets = "fluent-emoji-flat,noto,flat-color-icons";

// Polskie słowa, którymi najczęściej szuka się grafik — zbiory są opisane po angielsku
const QHash<QString, QString> &dictionary()
{
    static const QHash<QString, QString> d = [] {
        const char *pairs[][2] = {
            {"kawa", "coffee"}, {"kawy", "coffee"}, {"herbata", "tea"}, {"ciasto", "cake"}, {"ciasta", "cake"}, {"tort", "cake"},
            {"urodziny", "birthday"}, {"urodzinowy", "birthday"}, {"prezent", "gift"}, {"prezenty", "gift"}, {"balon", "balloon"},
            {"balony", "balloons"}, {"impreza", "party"}, {"przyjęcie", "party"}, {"ślub", "wedding"}, {"wesele", "wedding"},
            {"miłość", "love"}, {"serce", "heart"}, {"serca", "hearts"}, {"kwiat", "flower"}, {"kwiaty", "flowers"},
            {"róża", "rose"}, {"róże", "roses"}, {"tulipan", "tulip"}, {"liść", "leaf"}, {"liście", "leaves"}, {"drzewo", "tree"},
            {"drzewa", "trees"}, {"las", "forest"}, {"góry", "mountains"}, {"góra", "mountain"}, {"morze", "sea"}, {"plaża", "beach"},
            {"jezioro", "lake"}, {"rzeka", "river"}, {"niebo", "sky"}, {"chmura", "cloud"}, {"chmury", "clouds"}, {"słońce", "sun"},
            {"księżyc", "moon"}, {"gwiazda", "star"}, {"gwiazdy", "stars"}, {"deszcz", "rain"}, {"śnieg", "snow"}, {"zima", "winter"},
            {"lato", "summer"}, {"wiosna", "spring"}, {"jesień", "autumn"}, {"święta", "christmas"}, {"choinka", "christmas tree"},
            {"boże", "christmas"}, {"narodzenie", ""}, {"wielkanoc", "easter"}, {"jajko", "egg"}, {"jajka", "eggs"},
            {"halloween", "halloween"}, {"dynia", "pumpkin"}, {"pies", "dog"}, {"psy", "dogs"}, {"kot", "cat"}, {"koty", "cats"},
            {"ptak", "bird"}, {"ptaki", "birds"}, {"koń", "horse"}, {"ryba", "fish"}, {"motyl", "butterfly"}, {"zwierzęta", "animals"},
            {"zwierzę", "animal"}, {"dziecko", "child"}, {"dzieci", "children"}, {"rodzina", "family"}, {"ludzie", "people"},
            {"kobieta", "woman"}, {"mężczyzna", "man"}, {"przyjaciele", "friends"}, {"praca", "work"}, {"biuro", "office"},
            {"komputer", "computer"}, {"laptop", "laptop"}, {"telefon", "phone"}, {"szkoła", "school"}, {"książka", "book"},
            {"książki", "books"}, {"nauka", "education"}, {"ołówek", "pencil"}, {"muzyka", "music"}, {"koncert", "concert"},
            {"gitara", "guitar"}, {"pianino", "piano"}, {"taniec", "dance"}, {"sport", "sport"}, {"piłka", "ball"},
            {"rower", "bicycle"}, {"bieganie", "running"}, {"siłownia", "gym"}, {"joga", "yoga"}, {"jedzenie", "food"},
            {"obiad", "dinner"}, {"śniadanie", "breakfast"}, {"pizza", "pizza"}, {"owoce", "fruit"}, {"owoc", "fruit"},
            {"jabłko", "apple"}, {"truskawka", "strawberry"}, {"truskawki", "strawberries"}, {"warzywa", "vegetables"},
            {"chleb", "bread"}, {"piekarnia", "bakery"}, {"kawiarnia", "cafe"}, {"restauracja", "restaurant"}, {"wino", "wine"},
            {"piwo", "beer"}, {"lody", "ice cream"}, {"czekolada", "chocolate"}, {"miasto", "city"}, {"dom", "house"},
            {"domy", "houses"}, {"mieszkanie", "apartment"}, {"ogród", "garden"}, {"samochód", "car"}, {"auto", "car"},
            {"samolot", "airplane"}, {"podróż", "travel"}, {"podróże", "travel"}, {"wakacje", "vacation"}, {"walizka", "suitcase"},
            {"mapa", "map"}, {"zakupy", "shopping"}, {"sklep", "shop"}, {"promocja", "sale"}, {"wyprzedaż", "sale"},
            {"pieniądze", "money"}, {"karta", "card"}, {"koszyk", "cart"}, {"torba", "bag"}, {"ubrania", "clothes"},
            {"moda", "fashion"}, {"uroda", "beauty"}, {"kosmetyki", "cosmetics"}, {"fryzjer", "hairdresser"}, {"zdrowie", "health"},
            {"lekarz", "doctor"}, {"szpital", "hospital"}, {"apteka", "pharmacy"}, {"natura", "nature"}, {"woda", "water"},
            {"ogień", "fire"}, {"światło", "light"}, {"noc", "night"}, {"dzień", "day"}, {"zegar", "clock"}, {"kalendarz", "calendar"},
            {"czas", "time"}, {"strzałka", "arrow"}, {"strzałki", "arrows"}, {"krzyżyk", "cross"}, {"ptaszek", "check"},
            {"znak", "sign"}, {"pytanie", "question"}, {"uwaga", "warning"}, {"informacja", "info"}, {"poczta", "mail"},
            {"list", "letter"}, {"wiadomość", "message"}, {"rozmowa", "chat"}, {"lokalizacja", "location"}, {"pinezka", "pin"},
            {"ulubione", "favorite"}, {"polubienie", "like"}, {"kciuk", "thumbs up"}, {"uśmiech", "smile"}, {"buźka", "smiley"},
            {"śmiech", "laugh"}, {"smutek", "sad"}, {"korona", "crown"}, {"diament", "diamond"}, {"medal", "medal"},
            {"puchar", "trophy"}, {"nagroda", "award"}, {"flaga", "flag"}, {"polska", "poland"}, {"aparat", "camera"},
            {"zdjęcie", "photo"}, {"film", "movie"}, {"kino", "cinema"}, {"gra", "game"}, {"gry", "games"}, {"zabawki", "toys"},
            {"kościół", "church"}, {"krzyż", "cross"}, {"świeca", "candle"}, {"świece", "candles"}, {"wzór", "pattern"},
            {"tło", "background"}, {"tekstura", "texture"}, {"papier", "paper"}, {"drewno", "wood"}, {"kamień", "stone"},
            {"marmur", "marble"}, {"abstrakcja", "abstract"}, {"kolorowy", "colorful"}, {"kolorowe", "colorful"},
            {"czarny", "black"}, {"biały", "white"}, {"czerwony", "red"}, {"zielony", "green"}, {"niebieski", "blue"},
            {"żółty", "yellow"}, {"różowy", "pink"}, {"fioletowy", "purple"}, {"złoty", "gold"}, {"srebrny", "silver"},
            {"ramka", "frame"}, {"ramki", "frames"}, {"linia", "line"}, {"koło", "circle"}, {"kwadrat", "square"},
            {"trójkąt", "triangle"}, {"dekoracja", "decoration"}, {"dekoracje", "decorations"}, {"ozdoba", "ornament"},
            {"konfetti", "confetti"}, {"fajerwerki", "fireworks"}, {"sylwester", "new year"}, {"rocznica", "anniversary"},
            {"chrzest", "baptism"}, {"komunia", "communion"}, {"dziękuję", "thank you"}, {"powitanie", "welcome"},
            {"rolnictwo", "farm"}, {"wieś", "village"}, {"traktor", "tractor"}, {"narzędzia", "tools"}, {"młotek", "hammer"},
            {"budowa", "construction"}, {"remont", "renovation"}, {"sprzątanie", "cleaning"}, {"kuchnia", "kitchen"},
            {"gotowanie", "cooking"}, {"wegańskie", "vegan"}, {"ekologia", "ecology"}, {"recykling", "recycling"},
            {"energia", "energy"}, {"bezpieczeństwo", "security"}, {"kłódka", "lock"}, {"klucz", "key"}, {"ustawienia", "settings"},
            {"użytkownik", "user"}, {"osoba", "person"}, {"grupa", "group"}, {"zespół", "team"}, {"wykres", "chart"},
            {"statystyki", "statistics"}, {"sukces", "success"}, {"pomysł", "idea"}, {"żarówka", "light bulb"},
            {"rakieta", "rocket"}, {"kosmos", "space"}, {"planeta", "planet"}, {"ziemia", "earth"}, {"świat", "world"},
        };
        QHash<QString, QString> h;
        for (const auto &p : pairs)
            h.insert(QString::fromUtf8(p[0]), QString::fromUtf8(p[1]));
        return h;
    }();
    return d;
}

// Najpopularniejsze kroje z polskimi znakami — na górze listy „Więcej czcionek”
const QStringList &recommendedFonts()
{
    static const QStringList list{
        QStringLiteral("Montserrat"), QStringLiteral("Poppins"), QStringLiteral("Open Sans"), QStringLiteral("Lato"),
        QStringLiteral("Roboto"), QStringLiteral("Playfair Display"), QStringLiteral("Bebas Neue"), QStringLiteral("Oswald"),
        QStringLiteral("Raleway"), QStringLiteral("Lora"), QStringLiteral("Merriweather"), QStringLiteral("Dancing Script"),
        QStringLiteral("Great Vibes"), QStringLiteral("Pacifico"), QStringLiteral("Lobster"), QStringLiteral("Caveat"),
        QStringLiteral("Anton"), QStringLiteral("Archivo Black"), QStringLiteral("DM Serif Display"), QStringLiteral("Abril Fatface"),
        QStringLiteral("Nunito"), QStringLiteral("Quicksand"), QStringLiteral("Comfortaa"), QStringLiteral("Rubik"),
        QStringLiteral("Work Sans"), QStringLiteral("Josefin Sans"), QStringLiteral("Cormorant Garamond"), QStringLiteral("EB Garamond"),
        QStringLiteral("Libre Baskerville"), QStringLiteral("Cinzel"), QStringLiteral("Marcellus"), QStringLiteral("Prata"),
        QStringLiteral("Space Grotesk"), QStringLiteral("Manrope"), QStringLiteral("Manrope"), QStringLiteral("Plus Jakarta Sans"),
        QStringLiteral("Sora"), QStringLiteral("Syne"), QStringLiteral("Unbounded"), QStringLiteral("Righteous"),
        QStringLiteral("Bungee"), QStringLiteral("Permanent Marker"), QStringLiteral("Kaushan Script"), QStringLiteral("Courgette"),
        QStringLiteral("Satisfy"), QStringLiteral("Sacramento"), QStringLiteral("Allura"), QStringLiteral("Parisienne"),
        QStringLiteral("Alex Brush"), QStringLiteral("Amatic SC"), QStringLiteral("Kalam"), QStringLiteral("Fredoka"),
        QStringLiteral("Baloo 2"), QStringLiteral("Lilita One"), QStringLiteral("Alfa Slab One"), QStringLiteral("Roboto Slab"),
        QStringLiteral("Zilla Slab"), QStringLiteral("Barlow"), QStringLiteral("Barlow Condensed"), QStringLiteral("Exo 2"),
        QStringLiteral("Titillium Web"), QStringLiteral("Bodoni Moda"), QStringLiteral("Russo One"), QStringLiteral("Staatliches"),
        QStringLiteral("Passion One"), QStringLiteral("Bangers"), QStringLiteral("Press Start 2P"), QStringLiteral("Chakra Petch"),
    };
    return list;
}

QSet<QString> &previewFamilies()
{
    static QSet<QString> s;
    return s;
}

QString cacheDir()
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    QDir().mkpath(dir);
    return dir;
}

QString fileSafe(const QString &family)
{
    QString s = family;
    s.remove(QRegularExpression(QStringLiteral("[^A-Za-z0-9]")));
    return s;
}

}

Online::Online(QObject *parent)
    : QObject(parent)
    , m_net(new QNetworkAccessManager(this))
{
    m_net->setTransferTimeout(30000);
}

QNetworkReply *Online::get(const QString &url)
{
    QNetworkRequest req{QUrl(url)};
    req.setHeader(QNetworkRequest::UserAgentHeader, QString::fromLatin1(UserAgent));
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    return m_net->get(req);
}

QString Online::translate(const QString &query) const
{
    const QStringList words = query.toLower().split(QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts);
    QStringList out;
    bool any = false;
    for (const QString &w : words) {
        const auto it = dictionary().constFind(w);
        if (it != dictionary().cend()) {
            any = true;
            if (!it->isEmpty())
                out.append(*it);
        } else {
            out.append(w);
        }
    }
    return any ? out.join(QLatin1Char(' ')) : query.trimmed();
}

// ——— Zdjęcia (Wikimedia Commons) ———

// Tylko licencje bez „na tych samych warunkach”: CC0, CC BY 2.0/3.0/4.0 i domena publiczna
void Online::searchPhotos(const QString &query, int page)
{
    QUrlQuery q;
    q.addQueryItem(QStringLiteral("action"), QStringLiteral("query"));
    q.addQueryItem(QStringLiteral("format"), QStringLiteral("json"));
    q.addQueryItem(QStringLiteral("generator"), QStringLiteral("search"));
    q.addQueryItem(QStringLiteral("gsrsearch"), translate(query) + QStringLiteral(" filetype:bitmap haswbstatement:P275=Q6938433|P275=Q20007257|P275=Q14947546|P275=Q19125117|P6216=Q19652"));
    q.addQueryItem(QStringLiteral("gsrnamespace"), QStringLiteral("6"));
    q.addQueryItem(QStringLiteral("gsrlimit"), QStringLiteral("24"));
    q.addQueryItem(QStringLiteral("gsroffset"), QString::number((qMax(1, page) - 1) * 24));
    q.addQueryItem(QStringLiteral("prop"), QStringLiteral("imageinfo"));
    q.addQueryItem(QStringLiteral("iiprop"), QStringLiteral("url|size|extmetadata"));
    q.addQueryItem(QStringLiteral("iiextmetadatafilter"), QStringLiteral("LicenseShortName|Artist"));
    q.addQueryItem(QStringLiteral("iiurlwidth"), QStringLiteral("400"));
    QUrl url(QStringLiteral("https://commons.wikimedia.org/w/api.php"));
    url.setQuery(q);
    QNetworkReply *r = get(url.toString(QUrl::FullyEncoded));
    connect(r, &QNetworkReply::finished, this, [this, r, query, page] {
        r->deleteLater();
        const QJsonObject o = QJsonDocument::fromJson(r->readAll()).object();
        if (r->error() != QNetworkReply::NoError || o.contains(QStringLiteral("error"))) {
            Q_EMIT searchFailed(QStringLiteral("photos"));
            return;
        }
        // Strony przychodzą jako słownik — kolejność trafności jest w polu „index”
        QList<QJsonObject> pages;
        for (const QJsonValue &v : o.value(QStringLiteral("query")).toObject().value(QStringLiteral("pages")).toObject())
            pages.append(v.toObject());
        std::sort(pages.begin(), pages.end(), [](const QJsonObject &a, const QJsonObject &b) {
            return a.value(QStringLiteral("index")).toInt() < b.value(QStringLiteral("index")).toInt();
        });
        static const QRegularExpression tags(QStringLiteral("<[^>]*>"));
        static const QRegularExpression size(QStringLiteral("/\\d+px-"));
        QVariantList out;
        for (const QJsonObject &p : std::as_const(pages)) {
            const QJsonObject ii = p.value(QStringLiteral("imageinfo")).toArray().first().toObject();
            const QJsonObject meta = ii.value(QStringLiteral("extmetadata")).toObject();
            const QString license = meta.value(QStringLiteral("LicenseShortName")).toObject().value(QStringLiteral("value")).toString();
            QString artist = meta.value(QStringLiteral("Artist")).toObject().value(QStringLiteral("value")).toString();
            artist = artist.remove(tags).simplified();
            const int w = ii.value(QStringLiteral("width")).toInt(), h = ii.value(QStringLiteral("height")).toInt();
            const QString thumb = ii.value(QStringLiteral("thumburl")).toString();
            if (thumb.isEmpty() || w <= 0 || h <= 0)
                continue;
            // Do wstawienia wystarczy 2000 px na dłuższym boku (oryginały mają nawet kilkadziesiąt MB)
            const int longest = qMax(w, h);
            QString full = ii.value(QStringLiteral("url")).toString();
            if (longest > 2000)
                full = QString(thumb).replace(size, QStringLiteral("/%1px-").arg(w >= h ? 2000 : qRound(2000.0 * w / h)));
            const bool attribution = license.startsWith(QLatin1String("CC BY"));
            out.append(QVariantMap{{QStringLiteral("id"), QString::number(p.value(QStringLiteral("pageid")).toInt())},
                                   {QStringLiteral("url"), full},
                                   {QStringLiteral("thumb"), thumb},
                                   {QStringLiteral("fallback"), thumb},
                                   {QStringLiteral("title"), p.value(QStringLiteral("title")).toString().mid(5)},
                                   {QStringLiteral("license"), license},
                                   {QStringLiteral("credit"), attribution ? QStringLiteral("Fot. %1, %2, Wikimedia Commons").arg(artist.isEmpty() ? QStringLiteral("autor nieznany") : artist.left(80), license) : QString()},
                                   {QStringLiteral("ratio"), qreal(w) / h}});
        }
        Q_EMIT photosFound(query, page, out, o.contains(QStringLiteral("continue")));
    });
}

// ——— Ikony i naklejki (Iconify) ———

void Online::searchGraphics(const QString &query, const QString &kind, const QString &tint)
{
    const bool stickers = kind == QLatin1String("stickers");
    QUrlQuery q;
    q.addQueryItem(QStringLiteral("query"), translate(query));
    q.addQueryItem(QStringLiteral("limit"), QStringLiteral("64"));
    q.addQueryItem(QStringLiteral("prefixes"), QString::fromLatin1(stickers ? StickerSets : IconSets));
    QUrl url(QStringLiteral("https://api.iconify.design/search"));
    url.setQuery(q);
    QNetworkReply *r = get(url.toString(QUrl::FullyEncoded));
    connect(r, &QNetworkReply::finished, this, [this, r, query, kind, tint] {
        r->deleteLater();
        const QJsonObject o = QJsonDocument::fromJson(r->readAll()).object();
        if (r->error() != QNetworkReply::NoError || !o.contains(QStringLiteral("icons"))) {
            Q_EMIT searchFailed(kind);
            return;
        }
        // Rysunki ikon paczkami — jedno zapytanie na zestaw (pojedyncze pliki szybko trafiają na limit API)
        const QString dir = cacheDir() + QStringLiteral("/icons");
        QDir().mkpath(dir);
        QStringList names;
        QMap<QString, QStringList> missing;
        for (const QJsonValue &v : o.value(QStringLiteral("icons")).toArray()) {
            const QString name = v.toString();
            const int colon = name.indexOf(QLatin1Char(':'));
            if (colon < 0)
                continue;
            names.append(name);
            if (!QFileInfo::exists(dir + QLatin1Char('/') + QString(name).replace(QLatin1Char(':'), QStringLiteral("__")) + QStringLiteral(".svg")))
                missing[name.left(colon)].append(name.mid(colon + 1));
        }
        auto finish = [this, query, kind, tint, names, dir] {
            QVariantList out;
            for (const QString &name : names) {
                const QString file = dir + QLatin1Char('/') + QString(name).replace(QLatin1Char(':'), QStringLiteral("__")) + QStringLiteral(".svg");
                QFile f(file);
                if (!f.open(QIODevice::ReadOnly))
                    continue;
                QString thumb = file;
                // Podgląd ikony w kolorze motywu (ikony same w sobie mają currentColor, czyli czarny)
                if (!tint.isEmpty()) {
                    QByteArray data = f.readAll();
                    if (data.contains("currentColor")) {
                        thumb = file.chopped(4) + QStringLiteral("_") + QString(tint).remove(QLatin1Char('#')) + QStringLiteral(".svg");
                        if (!QFileInfo::exists(thumb)) {
                            QFile t(thumb);
                            if (t.open(QIODevice::WriteOnly))
                                t.write(data.replace("currentColor", tint.toLatin1()));
                        }
                    }
                }
                out.append(QVariantMap{{QStringLiteral("name"), name},
                                       {QStringLiteral("file"), file},
                                       {QStringLiteral("thumb"), QUrl::fromLocalFile(thumb).toString()}});
            }
            Q_EMIT graphicsFound(query, kind, out);
        };
        if (missing.isEmpty()) {
            finish();
            return;
        }
        auto left = std::make_shared<int>(missing.size());
        for (auto it = missing.cbegin(); it != missing.cend(); ++it) {
            const QString prefix = it.key();
            QNetworkReply *rr = get(QStringLiteral("https://api.iconify.design/%1.json?icons=%2").arg(prefix, it.value().join(QLatin1Char(','))));
            connect(rr, &QNetworkReply::finished, this, [rr, prefix, dir, left, finish] {
                rr->deleteLater();
                const QJsonObject set = QJsonDocument::fromJson(rr->readAll()).object();
                const QJsonObject icons = set.value(QStringLiteral("icons")).toObject();
                const int sw = set.value(QStringLiteral("width")).toInt(set.value(QStringLiteral("height")).toInt(16));
                const int sh = set.value(QStringLiteral("height")).toInt(16);
                for (auto ic = icons.constBegin(); ic != icons.constEnd(); ++ic) {
                    const QJsonObject i = ic.value().toObject();
                    const int w = i.value(QStringLiteral("width")).toInt(sw), h = i.value(QStringLiteral("height")).toInt(sh);
                    const int l = i.value(QStringLiteral("left")).toInt(0), t = i.value(QStringLiteral("top")).toInt(0);
                    const QString svg = QStringLiteral("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"%1 %2 %3 %4\" width=\"%3\" height=\"%4\">%5</svg>")
                                            .arg(l).arg(t).arg(w).arg(h).arg(i.value(QStringLiteral("body")).toString());
                    QFile f(dir + QLatin1Char('/') + prefix + QStringLiteral("__") + ic.key() + QStringLiteral(".svg"));
                    if (f.open(QIODevice::WriteOnly))
                        f.write(svg.toUtf8());
                }
                if (--*left == 0)
                    finish();
            });
        }
    });
}

void Online::fetch(const QString &url, const QString &tag)
{
    const QString base = cacheDir() + QStringLiteral("/net-") + QString::fromLatin1(QCryptographicHash::hash(url.toUtf8(), QCryptographicHash::Sha1).toHex());
    for (const QString &ext : {QStringLiteral("jpg"), QStringLiteral("png"), QStringLiteral("svg"), QStringLiteral("webp"), QStringLiteral("gif")}) {
        if (QFileInfo::exists(base + QLatin1Char('.') + ext)) {
            const QString path = base + QLatin1Char('.') + ext;
            QTimer::singleShot(0, this, [this, tag, path] { Q_EMIT fetched(tag, path); });
            return;
        }
    }
    QNetworkReply *r = get(url);
    connect(r, &QNetworkReply::finished, this, [this, r, base, tag] {
        r->deleteLater();
        const QByteArray data = r->readAll();
        if (r->error() != QNetworkReply::NoError || data.isEmpty()) {
            Q_EMIT fetchFailed(tag);
            return;
        }
        const QString type = r->header(QNetworkRequest::ContentTypeHeader).toString();
        const QString ext = type.contains(QLatin1String("svg")) ? QStringLiteral("svg") : type.contains(QLatin1String("png")) ? QStringLiteral("png")
                          : type.contains(QLatin1String("webp")) ? QStringLiteral("webp") : type.contains(QLatin1String("gif")) ? QStringLiteral("gif")
                          : QStringLiteral("jpg");
        QFile f(base + QLatin1Char('.') + ext);
        if (!f.open(QIODevice::WriteOnly) || f.write(data) != data.size()) {
            Q_EMIT fetchFailed(tag);
            return;
        }
        f.close();
        Q_EMIT fetched(tag, f.fileName());
    });
}

// ——— Czcionki ———

QString Online::fontsDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/fonts/aster-grafika");
}

QStringList Online::fontFiles(const QString &family)
{
    QStringList out;
    const QDir dir(fontsDir() + QLatin1Char('/') + fileSafe(family));
    for (const QString &f : dir.entryList({QStringLiteral("*.ttf")}, QDir::Files))
        out.append(dir.filePath(f));
    return out;
}

bool Online::previewOnly(const QString &family)
{
    return previewFamilies().contains(family);
}

void Online::loadDownloadedFonts()
{
    QDirIterator it(fontsDir(), {QStringLiteral("*.ttf")}, QDir::Files, QDirIterator::Subdirectories);
    while (it.hasNext())
        QFontDatabase::addApplicationFont(it.next());
}

void Online::setCatalog(const QByteArray &json)
{
    const QJsonArray all = QJsonDocument::fromJson(json).array();
    if (all.isEmpty())
        return;
    QHash<QString, int> rank;
    for (int i = 0; i < recommendedFonts().size(); ++i)
        rank.insert(recommendedFonts().at(i), i);
    QList<QVariantMap> list;
    for (const QJsonValue &v : all) {
        const QJsonObject o = v.toObject();
        if (o.value(QStringLiteral("type")).toString() != QLatin1String("google"))
            continue;
        if (!o.value(QStringLiteral("subsets")).toArray().contains(QStringLiteral("latin-ext")))
            continue;                                   // bez polskich znaków
        QVariantList weights;
        for (const QJsonValue &w : o.value(QStringLiteral("weights")).toArray())
            weights.append(w.toInt());
        const QString family = o.value(QStringLiteral("family")).toString();
        list.append({{QStringLiteral("family"), family},
                     {QStringLiteral("category"), o.value(QStringLiteral("category")).toString()},
                     {QStringLiteral("weights"), weights},
                     {QStringLiteral("italic"), o.value(QStringLiteral("styles")).toArray().contains(QStringLiteral("italic"))},
                     {QStringLiteral("license"), o.value(QStringLiteral("license")).toString()},
                     {QStringLiteral("rank"), rank.value(family, 100000)}});
    }
    std::stable_sort(list.begin(), list.end(), [](const QVariantMap &a, const QVariantMap &b) {
        const int ra = a.value(QStringLiteral("rank")).toInt(), rb = b.value(QStringLiteral("rank")).toInt();
        if (ra != rb)
            return ra < rb;
        return a.value(QStringLiteral("family")).toString().compare(b.value(QStringLiteral("family")).toString(), Qt::CaseInsensitive) < 0;
    });
    m_catalog.clear();
    for (const QVariantMap &m : std::as_const(list))
        m_catalog.append(m);
    m_catalogFailed = false;
    Q_EMIT fontCatalogChanged();
}

void Online::loadFontCatalog()
{
    if (!m_catalog.isEmpty() || m_catalogLoading)
        return;
    // Lista czcionek w pamięci podręcznej na tydzień
    const QString path = cacheDir() + QStringLiteral("/fonts.json");
    const QFileInfo fi(path);
    QFile f(path);
    if (fi.exists() && fi.lastModified().daysTo(QDateTime::currentDateTime()) < 7 && f.open(QIODevice::ReadOnly)) {
        setCatalog(f.readAll());
        if (!m_catalog.isEmpty())
            return;
    }
    m_catalogLoading = true;
    QNetworkReply *r = get(QStringLiteral("https://api.fontsource.org/v1/fonts"));
    connect(r, &QNetworkReply::finished, this, [this, r, path] {
        r->deleteLater();
        m_catalogLoading = false;
        const QByteArray data = r->readAll();
        if (r->error() == QNetworkReply::NoError)
            setCatalog(data);
        if (m_catalog.isEmpty()) {
            // Bez internetu — choć starsza lista, jeśli jest
            QFile old(path);
            if (old.open(QIODevice::ReadOnly))
                setCatalog(old.readAll());
            if (m_catalog.isEmpty()) {
                m_catalogFailed = true;
                Q_EMIT fontCatalogChanged();
            }
            return;
        }
        QFile out(path);
        if (out.open(QIODevice::WriteOnly))
            out.write(data);
    });
}

// Pliki TTF z Google Fonts: dla nieznanej przeglądarki CSS podaje zwykłe pliki TrueType (styl, waga, adres)
void Online::fontFaces(const QString &family, const QString &spec, std::function<void(QList<QPair<QString, QString>>)> done)
{
    QString name = family;
    name.replace(QLatin1Char(' '), QLatin1Char('+'));
    QNetworkReply *r = get(QStringLiteral("https://fonts.googleapis.com/css2?family=") + name + spec);
    connect(r, &QNetworkReply::finished, this, [r, done] {
        r->deleteLater();
        QList<QPair<QString, QString>> faces;
        if (r->error() == QNetworkReply::NoError) {
            static const QRegularExpression face(QStringLiteral("font-style:\\s*(\\w+);\\s*font-weight:\\s*(\\d+);[^}]*?src:\\s*url\\(([^)]+)\\)"));
            const QString css = QString::fromUtf8(r->readAll());
            for (auto it = face.globalMatch(css); it.hasNext();) {
                const QRegularExpressionMatch m = it.next();
                faces.append({m.captured(2) + (m.captured(1) == QLatin1String("italic") ? QStringLiteral("i") : QString()), m.captured(3)});
            }
        }
        done(faces);
    });
}

void Online::previewFont(const QString &family, const QString &text)
{
    if (family.isEmpty() || m_previews.contains(family) || m_pending.contains(family) || QFontDatabase::hasFamily(family))
        return;
    m_pending.insert(family);
    QPointer<Online> self(this);
    fontFaces(family, QStringLiteral("&text=") + QString::fromLatin1(QUrl::toPercentEncoding(family + text)), [self, family](const QList<QPair<QString, QString>> &faces) {
        if (!self)
            return;
        if (faces.isEmpty()) {
            self->m_pending.remove(family);
            return;
        }
        QNetworkReply *r = self->get(faces.constFirst().second);
        connect(r, &QNetworkReply::finished, self, [self, r, family] {
            r->deleteLater();
            self->m_pending.remove(family);
            if (r->error() != QNetworkReply::NoError || !self->fontFiles(family).isEmpty())
                return;
            const int id = QFontDatabase::addApplicationFontFromData(r->readAll());
            if (id < 0)
                return;
            self->m_previews.insert(family, id);
            previewFamilies().insert(family);
            Q_EMIT self->fontPreviewReady(family);
        });
    });
}

void Online::installFont(const QString &family)
{
    if (!fontFiles(family).isEmpty()) {
        QTimer::singleShot(0, this, [this, family] { Q_EMIT fontInstalled(family); });
        return;
    }
    const QString key = QStringLiteral("install:") + family;
    if (m_pending.contains(key))
        return;
    // Licencję (katalog w repozytorium) i grubości zna dopiero lista czcionek — najpierw ona
    if (m_catalog.isEmpty() && !m_catalogFailed) {
        loadFontCatalog();
        if (m_catalog.isEmpty()) {
            m_pending.insert(key);
            auto *ctx = new QObject(this);
            connect(this, &Online::fontCatalogChanged, ctx, [this, ctx, key, family] {
                ctx->deleteLater();
                m_pending.remove(key);
                installFont(family);
            });
            return;
        }
    }
    QVariantMap info;
    for (const QVariant &v : std::as_const(m_catalog))
        if (v.toMap().value(QStringLiteral("family")).toString() == family)
            info = v.toMap();
    m_pending.insert(key);

    // Pliki z repozytorium Google Fonts (pełne rodziny z poprawnymi nazwami, często czcionki zmienne);
    // gdy się nie uda — pliki z Google Fonts CSS
    const QString license = info.value(QStringLiteral("license")).toString();
    const QString dir = license.startsWith(QLatin1String("Apache")) ? QStringLiteral("apache") : license.startsWith(QLatin1String("UFL")) ? QStringLiteral("ufl") : QStringLiteral("ofl");
    const QString base = QStringLiteral("https://raw.githubusercontent.com/google/fonts/main/%1/%2/").arg(dir, fileSafe(family).toLower());
    QNetworkReply *meta = get(base + QStringLiteral("METADATA.pb"));
    connect(meta, &QNetworkReply::finished, this, [this, meta, family, key, base, info] {
        meta->deleteLater();
        QList<QPair<QString, QString>> files;
        if (meta->error() == QNetworkReply::NoError) {
            static const QRegularExpression file(QStringLiteral("filename:\\s*\"([^\"]+\\.ttf)\""));
            for (auto it = file.globalMatch(QString::fromUtf8(meta->readAll())); it.hasNext();) {
                const QString name = it.next().captured(1);
                files.append({base + QString::fromLatin1(QUrl::toPercentEncoding(name)), name});
            }
        }
        if (!files.isEmpty()) {
            downloadFaces(family, key, files);
            return;
        }
        QStringList weights;
        for (const QVariant &w : info.value(QStringLiteral("weights")).toList())
            weights.append(QString::number(w.toInt()));
        if (weights.isEmpty())
            weights.append(QStringLiteral("400"));
        QString spec;
        if (info.value(QStringLiteral("italic")).toBool()) {
            QStringList tuples;
            for (const QString &w : weights)
                tuples.append(QStringLiteral("0,") + w);
            for (const QString &w : weights)
                tuples.append(QStringLiteral("1,") + w);
            spec = QStringLiteral(":ital,wght@") + tuples.join(QLatin1Char(';'));
        } else if (weights.size() > 1 || weights.constFirst() != QLatin1String("400")) {
            spec = QStringLiteral(":wght@") + weights.join(QLatin1Char(';'));
        }
        QPointer<Online> self(this);
        fontFaces(family, spec, [self, family, key](const QList<QPair<QString, QString>> &faces) {
            if (!self)
                return;
            QList<QPair<QString, QString>> files;
            for (const auto &face : faces)
                files.append({face.second, fileSafe(family) + QLatin1Char('-') + face.first + QStringLiteral(".ttf")});
            self->downloadFaces(family, key, files);
        });
    });
}

// Pobranie plików (adres, nazwa) całej rodziny: na miejsce trafiają dopiero wszystkie naraz
void Online::downloadFaces(const QString &family, const QString &key, const QList<QPair<QString, QString>> &files)
{
    if (files.isEmpty()) {
        m_pending.remove(key);
        Q_EMIT fontFailed(family);
        return;
    }
    const QString dir = fontsDir() + QLatin1Char('/') + fileSafe(family);
    QDir(dir + QStringLiteral(".part")).removeRecursively();
    QDir().mkpath(dir + QStringLiteral(".part"));
    auto left = std::make_shared<int>(files.size());
    auto ok = std::make_shared<bool>(true);
    for (const auto &f : files) {
        QNetworkReply *r = get(f.first);
        const QString path = dir + QStringLiteral(".part/") + f.second;
        connect(r, &QNetworkReply::finished, this, [this, r, path, dir, family, key, left, ok] {
            r->deleteLater();
            const QByteArray data = r->readAll();
            QFile out(path);
            if (r->error() != QNetworkReply::NoError || data.isEmpty() || !out.open(QIODevice::WriteOnly) || out.write(data) != data.size())
                *ok = false;
            out.close();
            if (--*left > 0)
                return;
            m_pending.remove(key);
            if (!*ok) {
                QDir(dir + QStringLiteral(".part")).removeRecursively();
                Q_EMIT fontFailed(family);
                return;
            }
            QDir(dir).removeRecursively();
            QDir().rename(dir + QStringLiteral(".part"), dir);
            if (m_previews.contains(family))
                QFontDatabase::removeApplicationFont(m_previews.take(family));
            previewFamilies().remove(family);
            for (const QString &p : fontFiles(family))
                QFontDatabase::addApplicationFont(p);
            Q_EMIT fontInstalled(family);
        });
    }
}
