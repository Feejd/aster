#include "project.h"

#include <QDate>
#include <QDateTime>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QImageReader>
#include <QJsonArray>
#include <QJsonDocument>
#include <QLocale>
#include <QSaveFile>
#include <QStandardPaths>
#include <QUrl>
#include <QUuid>
#include <QXmlStreamWriter>
#include <QtMath>

#include <cmath>

#include <mlt++/Mlt.h>

namespace {

const QStringList imageExt = {QStringLiteral("jpg"), QStringLiteral("jpeg"), QStringLiteral("png"), QStringLiteral("webp"),
                              QStringLiteral("bmp"), QStringLiteral("gif"), QStringLiteral("heic"), QStringLiteral("heif"),
                              QStringLiteral("avif"), QStringLiteral("tif"), QStringLiteral("tiff")};
const QStringList audioExt = {QStringLiteral("mp3"), QStringLiteral("m4a"), QStringLiteral("aac"), QStringLiteral("ogg"),
                              QStringLiteral("oga"), QStringLiteral("opus"), QStringLiteral("flac"), QStringLiteral("wav"),
                              QStringLiteral("wma")};

constexpr int ImageFrames = 3 * Project::Fps;      // zdjęcie na osi: 3 s
constexpr int TextFrames = 3 * Project::Fps;
constexpr int MinFrames = 6;

// Gotowe style napisów. Rozmiary — ułamek krótszego boku kadru, położenie — pionowo w kadrze.
struct Style {
    const char *id, *name, *fg, *bg, *ol;
    double size, outline; int weight; const char *place; bool upper;
};
const Style styles[] = {
    {"klasyczny", "Klasyczny", "#FFFFFF", "#00000000", "#000000", 0.072, 0.09, 700, "bottom", false},
    {"pasek", "Pasek", "#FFFFFF", "#B0000000", "#00000000", 0.058, 0, 600, "bottom", false},
    {"naglowek", "Nagłówek", "#FFFFFF", "#00000000", "#000000", 0.115, 0.07, 900, "middle", true},
    {"zolty", "Żółty", "#FFD84D", "#00000000", "#000000", 0.08, 0.1, 800, "lower", false},
    {"etykieta", "Etykieta", "#FFFFFF", "#FFFF3B6B", "#00000000", 0.062, 0, 700, "top", false},
    {"delikatny", "Delikatny", "#FFFFFF", "#00000000", "#90000000", 0.052, 0.05, 400, "bottom", false},
};
// Wygląd klipu (filtry kolorów) i animacje napisów
struct Named { const char *id, *name; };
const Named lookTable[] = {
    {"", "Bez filtra"}, {"zywy", "Żywy"}, {"cieply", "Ciepły"}, {"chlodny", "Chłodny"},
    {"pogodny", "Pogodny"}, {"kino", "Kino"}, {"retro", "Retro"}, {"czarnobialy", "Czarno-biały"},
};
const Named animationTable[] = {
    {"brak", "Bez animacji"}, {"pojawianie", "Pojawianie"}, {"wjazd", "Wjazd od dołu"},
    {"bok", "Wjazd z boku"}, {"pisanie", "Pisanie"},
};

const Named transitionTable[] = {
    {"fade", "Przenikanie"}, {"black", "Przez czerń"}, {"white", "Błysk"}, {"blur", "Rozmycie"},
    {"pushleft", "Przesunięcie"}, {"pushup", "W górę"}, {"slide", "Wsunięcie"}, {"whip", "Smuga"},
    {"zoomin", "Przybliżenie"}, {"zoomout", "Oddalenie"}, {"spin", "Obrót"}, {"wipe", "Kurtyna"},
    {"circle", "Koło"},
};
const Named motionTable[] = {
    {"", "Bez ruchu"}, {"zoomin", "Najazd"}, {"zoomout", "Odjazd"}, {"panleft", "W lewo"},
    {"panright", "W prawo"}, {"pulse", "Puls"}, {"shake", "Drgania"},
};

// Obraz przejścia „luma” (ciemne miejsca zmieniają się pierwsze): kurtyna od lewej albo koło od środka.
// Rysowany raz dla danego rozmiaru, w pamięci podręcznej programu.
QString lumaFile(const QString &kind, int w, int h)
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + QStringLiteral("/lumas");
    const int lw = qMax(16, w / 4), lh = qMax(16, h / 4);
    const QString path = dir + QStringLiteral("/%1-%2x%3.png").arg(kind).arg(lw).arg(lh);
    if (QFileInfo::exists(path))
        return path;
    QDir().mkpath(dir);
    QImage img(lw, lh, QImage::Format_Grayscale8);
    const double maxR = std::hypot(lw / 2.0, lh / 2.0);
    for (int yy = 0; yy < lh; ++yy) {
        uchar *line = img.scanLine(yy);
        for (int xx = 0; xx < lw; ++xx) {
            const double v = kind == QLatin1String("circle") ? std::hypot(xx - lw / 2.0, yy - lh / 2.0) / maxR : double(xx) / (lw - 1);
            line[xx] = uchar(qBound(0, int(v * 255), 255));
        }
    }
    img.save(path);
    return path;
}

const Style &styleOf(const QString &id)
{
    for (const Style &s : styles)
        if (id == QLatin1String(s.id))
            return s;
    return styles[0];
}

// Łamanie długiego tekstu na wiersze (qtext sam nie zawija)
QString wrapText(const QString &text, int maxChars)
{
    QStringList out;
    for (const QString &para : text.split(QLatin1Char('\n'))) {
        QString line;
        for (const QString &word : para.split(QLatin1Char(' '), Qt::SkipEmptyParts)) {
            if (!line.isEmpty() && line.size() + 1 + word.size() > maxChars) {
                out << line;
                line.clear();
            }
            line += (line.isEmpty() ? QString() : QStringLiteral(" ")) + word;
        }
        out << line;
    }
    return out.join(QLatin1Char('\n'));
}

Mlt::Profile &probeProfile()
{
    static Mlt::Profile *p = [] {
        auto *pr = new Mlt::Profile;
        pr->set_width(640);
        pr->set_height(360);
        pr->set_frame_rate(Project::Fps, 1);
        pr->set_sample_aspect(1, 1);
        pr->set_progressive(1);
        pr->set_explicit(1);
        return pr;
    }();
    return *p;
}

} // namespace

Project::Project(QObject *parent)
    : QObject(parent)
{
    m_saveTimer.setSingleShot(true);
    m_saveTimer.setInterval(600);
    connect(&m_saveTimer, &QTimer::timeout, this, &Project::save);
    loadProjects();

}

Project *Project::instance()
{
    static Project *p = new Project;
    return p;
}

Project *Project::create(QQmlEngine *, QJSEngine *engine)
{
    Project *p = instance();
    engine->setObjectOwnership(p, QJSEngine::CppOwnership);
    return p;
}

Project::~Project()
{
    if (m_saveTimer.isActive())
        save();
}

int Project::width() const
{
    return m_format == QLatin1String("16:9") ? 1920 : 1080;
}

int Project::height() const
{
    return m_format == QLatin1String("9:16") ? 1920 : 1080;
}

void Project::setName(const QString &name)
{
    const QString n = name.trimmed();
    if (n.isEmpty() || n == m_name)
        return;
    snapshot();
    m_name = n;
    commit();
}

QVariantList Project::media() const
{
    QVariantList l;
    for (const Media &m : m_media)
        l << QVariantMap{{QStringLiteral("path"), m.path}, {QStringLiteral("kind"), m.kind}, {QStringLiteral("name"), m.name},
                         {QStringLiteral("frames"), m.frames}, {QStringLiteral("thumb"), m.kind == QLatin1String("audio") ? QString() : thumbUrl(m.path, m.frames / 5)}};
    return l;
}

QVariantList Project::clips() const
{
    QVariantList l;
    for (int i = 0; i < m_clips.size(); ++i) {
        const Clip &c = m_clips.at(i);
        l << QVariantMap{{QStringLiteral("id"), c.id}, {QStringLiteral("path"), c.path}, {QStringLiteral("kind"), c.kind},
                         {QStringLiteral("name"), c.name}, {QStringLiteral("in"), c.in}, {QStringLiteral("out"), c.out},
                         {QStringLiteral("speed"), c.speed}, {QStringLiteral("volume"), c.volume}, {QStringLiteral("fill"), c.fill},
                         {QStringLiteral("fade"), c.fade}, {QStringLiteral("srcFrames"), c.srcFrames},
                         {QStringLiteral("look"), c.look}, {QStringLiteral("brightness"), c.brightness},
                         {QStringLiteral("fit"), c.blurBg ? QStringLiteral("blur") : c.fill ? QStringLiteral("fill") : QStringLiteral("fit")},
                         {QStringLiteral("flip"), c.flip}, {QStringLiteral("motion"), c.motion}, {QStringLiteral("trans"), c.trans},
                         {QStringLiteral("contrast"), c.contrast}, {QStringLiteral("saturation"), c.saturation},
                         {QStringLiteral("start"), c.start}, {QStringLiteral("length"), c.length}, {QStringLiteral("index"), i}};
    }
    return l;
}

QVariantList Project::texts() const
{
    QVariantList l;
    for (const Text &t : m_texts)
        l << QVariantMap{{QStringLiteral("id"), t.id}, {QStringLiteral("text"), t.text}, {QStringLiteral("style"), t.style},
                         {QStringLiteral("anim"), t.anim}, {QStringLiteral("start"), t.start}, {QStringLiteral("length"), t.length},
                         {QStringLiteral("caption"), t.caption}, {QStringLiteral("x"), t.x}, {QStringLiteral("y"), t.y},
                         {QStringLiteral("scale"), t.scale}, {QStringLiteral("color"), t.color}};
    return l;
}

QVariantList Project::overlays() const
{
    QVariantList l;
    for (const Overlay &o : m_overlays)
        l << QVariantMap{{QStringLiteral("id"), o.id}, {QStringLiteral("path"), o.path}, {QStringLiteral("kind"), o.kind},
                         {QStringLiteral("name"), o.name}, {QStringLiteral("start"), o.start}, {QStringLiteral("in"), o.in},
                         {QStringLiteral("out"), o.out}, {QStringLiteral("length"), o.out - o.in + 1}, {QStringLiteral("srcFrames"), o.srcFrames},
                         {QStringLiteral("aspect"), o.shape == QLatin1String("circle") ? 1.0 : o.aspect}, {QStringLiteral("x"), o.x},
                         {QStringLiteral("y"), o.y}, {QStringLiteral("scale"), o.scale}, {QStringLiteral("rotation"), o.rotation},
                         {QStringLiteral("opacity"), o.opacity}, {QStringLiteral("volume"), o.volume}, {QStringLiteral("shape"), o.shape},
                         {QStringLiteral("chroma"), o.chroma}, {QStringLiteral("key"), o.key}, {QStringLiteral("variance"), o.variance},
                         {QStringLiteral("anim"), o.anim}};
    return l;
}

QVariantList Project::music() const
{
    QVariantList l;
    for (const Music &m : m_music)
        l << QVariantMap{{QStringLiteral("id"), m.id}, {QStringLiteral("path"), m.path}, {QStringLiteral("name"), m.name},
                         {QStringLiteral("start"), m.start}, {QStringLiteral("in"), m.in}, {QStringLiteral("out"), m.out},
                         {QStringLiteral("length"), m.out - m.in + 1}, {QStringLiteral("srcFrames"), m.srcFrames},
                         {QStringLiteral("volume"), m.volume}, {QStringLiteral("fadeOut"), m.fadeOut}};
    return l;
}

QVariantList Project::looks() const
{
    QVariantList l;
    for (const Named &n : lookTable)
        l << QVariantMap{{QStringLiteral("id"), QString::fromLatin1(n.id)}, {QStringLiteral("name"), QString::fromUtf8(n.name)}};
    return l;
}

QVariantList Project::transitions() const
{
    QVariantList l;
    for (const Named &n : transitionTable)
        l << QVariantMap{{QStringLiteral("id"), QString::fromLatin1(n.id)}, {QStringLiteral("name"), QString::fromUtf8(n.name)}};
    return l;
}

QVariantList Project::motions() const
{
    QVariantList l;
    for (const Named &n : motionTable)
        l << QVariantMap{{QStringLiteral("id"), QString::fromLatin1(n.id)}, {QStringLiteral("name"), QString::fromUtf8(n.name)}};
    return l;
}

QVariantList Project::textAnimations() const
{
    QVariantList l;
    for (const Named &n : animationTable)
        l << QVariantMap{{QStringLiteral("id"), QString::fromLatin1(n.id)}, {QStringLiteral("name"), QString::fromUtf8(n.name)}};
    return l;
}

Project::FilterList Project::lookFilters(const QString &look, double brightness, double contrast, double saturation)
{
    using P = QList<QPair<QString, QString>>;
    FilterList f;
    const QString eq = QStringLiteral("avfilter.eq");
    if (look == QLatin1String("zywy"))
        f << qMakePair(eq, P{{QStringLiteral("av.saturation"), QStringLiteral("1.4")}, {QStringLiteral("av.contrast"), QStringLiteral("1.06")}});
    else if (look == QLatin1String("cieply"))
        f << qMakePair(QStringLiteral("avfilter.colortemperature"), P{{QStringLiteral("av.temperature"), QStringLiteral("3800")}})
          << qMakePair(eq, P{{QStringLiteral("av.saturation"), QStringLiteral("1.08")}});
    else if (look == QLatin1String("chlodny"))
        f << qMakePair(QStringLiteral("avfilter.colortemperature"), P{{QStringLiteral("av.temperature"), QStringLiteral("10000")}});
    else if (look == QLatin1String("pogodny"))
        f << qMakePair(eq, P{{QStringLiteral("av.brightness"), QStringLiteral("0.05")}, {QStringLiteral("av.saturation"), QStringLiteral("1.18")},
                             {QStringLiteral("av.gamma"), QStringLiteral("1.08")}});
    else if (look == QLatin1String("kino"))
        f << qMakePair(QStringLiteral("avfilter.colorbalance"), P{{QStringLiteral("av.bs"), QStringLiteral("0.15")}, {QStringLiteral("av.rh"), QStringLiteral("0.12")},
                                                                  {QStringLiteral("av.bh"), QStringLiteral("-0.1")}})
          << qMakePair(eq, P{{QStringLiteral("av.saturation"), QStringLiteral("0.9")}, {QStringLiteral("av.contrast"), QStringLiteral("1.1")}});
    else if (look == QLatin1String("retro"))
        f << qMakePair(QStringLiteral("avfilter.curves"), P{{QStringLiteral("av.preset"), QStringLiteral("vintage")}});
    else if (look == QLatin1String("czarnobialy"))
        f << qMakePair(eq, P{{QStringLiteral("av.saturation"), QStringLiteral("0")}, {QStringLiteral("av.contrast"), QStringLiteral("1.1")}});
    // Ręczna korekcja na końcu (po filtrze)
    if (!qFuzzyIsNull(brightness) || !qFuzzyCompare(contrast, 1.0) || !qFuzzyCompare(saturation, 1.0))
        f << qMakePair(eq, P{{QStringLiteral("av.brightness"), QString::number(brightness, 'g', 4)},
                             {QStringLiteral("av.contrast"), QString::number(contrast, 'g', 4)},
                             {QStringLiteral("av.saturation"), QString::number(saturation, 'g', 4)}});
    return f;
}

QVariantList Project::textStyles() const
{
    QVariantList l;
    for (const Style &s : styles)
        l << QVariantMap{{QStringLiteral("id"), QString::fromLatin1(s.id)}, {QStringLiteral("name"), QString::fromUtf8(s.name)},
                         {QStringLiteral("fg"), QString::fromLatin1(s.fg)}, {QStringLiteral("bg"), QString::fromLatin1(s.bg)},
                         {QStringLiteral("ol"), QString::fromLatin1(s.ol)}, {QStringLiteral("outline"), s.outline},
                         {QStringLiteral("weight"), s.weight}, {QStringLiteral("place"), QString::fromLatin1(s.place)},
                         {QStringLiteral("upper"), s.upper}, {QStringLiteral("size"), s.size}};
    return l;
}

// ——— Projekty ———

QString Project::projectsDir() const
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + QStringLiteral("/projects");
    QDir().mkpath(dir);
    return dir;
}

QString Project::newId() const
{
    return QUuid::createUuid().toString(QUuid::Id128).left(12);
}

void Project::loadProjects()
{
    QList<QVariantMap> list;
    const QDir dir(projectsDir());
    for (const QFileInfo &fi : dir.entryInfoList({QStringLiteral("*.json")}, QDir::Files)) {
        QFile f(fi.absoluteFilePath());
        if (!f.open(QIODevice::ReadOnly))
            continue;
        const QJsonObject o = QJsonDocument::fromJson(f.readAll()).object();
        const QJsonArray clips = o.value(QLatin1String("clips")).toArray();
        QString thumb;
        if (!clips.isEmpty()) {
            const QJsonObject c = clips.first().toObject();
            thumb = thumbUrl(c.value(QLatin1String("path")).toString(), c.value(QLatin1String("in")).toInt() + 15);
        }
        list << QVariantMap{{QStringLiteral("id"), fi.completeBaseName()}, {QStringLiteral("name"), o.value(QLatin1String("name")).toString()},
                            {QStringLiteral("format"), o.value(QLatin1String("format")).toString()},
                            {QStringLiteral("modified"), fi.lastModified().toMSecsSinceEpoch()},
                            {QStringLiteral("duration"), o.value(QLatin1String("duration")).toInt()}, {QStringLiteral("thumb"), thumb}};
    }
    std::sort(list.begin(), list.end(), [](const QVariantMap &a, const QVariantMap &b) {
        return a.value(QStringLiteral("modified")).toLongLong() > b.value(QStringLiteral("modified")).toLongLong();
    });
    m_projects.clear();
    for (const QVariantMap &m : list)
        m_projects << m;
    Q_EMIT projectsChanged();
}

void Project::newProject(const QString &format)
{

    closeProject();
    m_id = newId();
    m_format = (format == QLatin1String("16:9") || format == QLatin1String("1:1")) ? format : QStringLiteral("9:16");
    const QLocale pl(QLocale::Polish);
    const QString base = QStringLiteral("Film z ") + pl.toString(QDate::currentDate(), QStringLiteral("d MMMM"));
    m_name = base;
    for (int i = 2;; ++i) {          // „Film z 3 listopada (2)”, gdy taki już jest
        bool taken = false;
        for (const QVariant &v : std::as_const(m_projects))
            taken |= v.toMap().value(QStringLiteral("name")).toString() == m_name;
        if (!taken)
            break;
        m_name = base + QStringLiteral(" (%1)").arg(i);
    }
    m_created = QDateTime::currentMSecsSinceEpoch();
    m_fadeIn = m_fadeOut = false;
    m_undo.clear();
    m_redo.clear();
    layout();
    ++m_revision;
    Q_EMIT openChanged();
    Q_EMIT changed();
}

bool Project::openProject(const QString &id)
{
    QFile f(projectsDir() + QLatin1Char('/') + id + QStringLiteral(".json"));
    if (!f.open(QIODevice::ReadOnly))
        return false;
    const QJsonObject o = QJsonDocument::fromJson(f.readAll()).object();
    closeProject();
    m_id = id;
    fromJson(o);
    m_created = qint64(o.value(QLatin1String("created")).toDouble());
    m_undo.clear();
    m_redo.clear();
    layout();
    ++m_revision;
    Q_EMIT openChanged();
    Q_EMIT changed();
    return true;
}

void Project::closeProject()
{
    if (m_id.isEmpty())
        return;
    if (m_clips.isEmpty() && m_texts.isEmpty() && m_music.isEmpty()) {
        m_saveTimer.stop();
        QFile::remove(projectsDir() + QLatin1Char('/') + m_id + QStringLiteral(".json"));   // pusty projekt nie zostaje na liście
    } else {
        save();
    }
    m_id.clear();
    m_media.clear();
    m_clips.clear();
    m_texts.clear();
    m_music.clear();
    m_overlays.clear();
    m_undo.clear();
    m_redo.clear();
    layout();
    ++m_revision;
    loadProjects();
    Q_EMIT openChanged();
    Q_EMIT changed();
}

void Project::deleteProject(const QString &id)
{
    if (id.isEmpty() || id.contains(QLatin1Char('/')))
        return;
    if (id == m_id)
        closeProject();
    QFile::remove(projectsDir() + QLatin1Char('/') + id + QStringLiteral(".json"));
    loadProjects();
}

QString Project::guessFormat(const QStringList &files) const
{
    for (const QString &f : files) {
        const Media *m = const_cast<Project *>(this)->probe(toPath(f));
        if (m && m->w > 0 && m->h > 0) {
            const double r = double(m->w) / m->h;
            return r < 0.8 ? QStringLiteral("9:16") : r > 1.25 ? QStringLiteral("16:9") : QStringLiteral("1:1");
        }
    }
    return QStringLiteral("9:16");
}

void Project::save()
{
    m_saveTimer.stop();
    if (m_id.isEmpty())
        return;
    QJsonObject o = toJson();
    o.insert(QStringLiteral("created"), double(m_created));
    o.insert(QStringLiteral("duration"), m_duration);
    QSaveFile f(projectsDir() + QLatin1Char('/') + m_id + QStringLiteral(".json"));
    if (f.open(QIODevice::WriteOnly)) {
        f.write(QJsonDocument(o).toJson(QJsonDocument::Indented));
        f.commit();
    }
}

QJsonObject Project::toJson() const
{
    QJsonArray media, clips, texts, music, overlays;
    for (const Overlay &o : m_overlays)
        overlays << QJsonObject{{QStringLiteral("id"), o.id}, {QStringLiteral("path"), o.path}, {QStringLiteral("kind"), o.kind},
                                {QStringLiteral("start"), o.start}, {QStringLiteral("in"), o.in}, {QStringLiteral("out"), o.out},
                                {QStringLiteral("srcFrames"), o.srcFrames}, {QStringLiteral("aspect"), o.aspect}, {QStringLiteral("x"), o.x},
                                {QStringLiteral("y"), o.y}, {QStringLiteral("scale"), o.scale}, {QStringLiteral("rotation"), o.rotation},
                                {QStringLiteral("opacity"), o.opacity}, {QStringLiteral("volume"), o.volume}, {QStringLiteral("shape"), o.shape},
                                {QStringLiteral("chroma"), o.chroma}, {QStringLiteral("key"), o.key}, {QStringLiteral("variance"), o.variance},
                                {QStringLiteral("anim"), o.anim}};
    for (const Media &m : m_media)
        media << QJsonObject{{QStringLiteral("path"), m.path}, {QStringLiteral("kind"), m.kind}, {QStringLiteral("frames"), m.frames},
                             {QStringLiteral("w"), m.w}, {QStringLiteral("h"), m.h}, {QStringLiteral("audio"), m.audio}};
    for (const Clip &c : m_clips)
        clips << QJsonObject{{QStringLiteral("id"), c.id}, {QStringLiteral("path"), c.path}, {QStringLiteral("kind"), c.kind},
                             {QStringLiteral("in"), c.in}, {QStringLiteral("out"), c.out}, {QStringLiteral("speed"), c.speed},
                             {QStringLiteral("volume"), c.volume}, {QStringLiteral("fill"), c.fill}, {QStringLiteral("fade"), c.fade},
                             {QStringLiteral("srcFrames"), c.srcFrames}, {QStringLiteral("look"), c.look},
                             {QStringLiteral("brightness"), c.brightness}, {QStringLiteral("contrast"), c.contrast},
                             {QStringLiteral("saturation"), c.saturation}, {QStringLiteral("blurBg"), c.blurBg},
                             {QStringLiteral("flip"), c.flip}, {QStringLiteral("motion"), c.motion}, {QStringLiteral("trans"), c.trans}};
    for (const Text &t : m_texts)
        texts << QJsonObject{{QStringLiteral("id"), t.id}, {QStringLiteral("text"), t.text}, {QStringLiteral("style"), t.style},
                             {QStringLiteral("anim"), t.anim}, {QStringLiteral("caption"), t.caption},
                             {QStringLiteral("x"), t.x}, {QStringLiteral("y"), t.y}, {QStringLiteral("scale"), t.scale}, {QStringLiteral("color"), t.color},
                             {QStringLiteral("start"), t.start}, {QStringLiteral("length"), t.length}};
    for (const Music &m : m_music)
        music << QJsonObject{{QStringLiteral("id"), m.id}, {QStringLiteral("path"), m.path}, {QStringLiteral("start"), m.start},
                             {QStringLiteral("in"), m.in}, {QStringLiteral("out"), m.out}, {QStringLiteral("srcFrames"), m.srcFrames},
                             {QStringLiteral("volume"), m.volume}, {QStringLiteral("fadeOut"), m.fadeOut}};
    return QJsonObject{{QStringLiteral("version"), 1}, {QStringLiteral("name"), m_name}, {QStringLiteral("format"), m_format},
                       {QStringLiteral("fps"), Fps}, {QStringLiteral("fadeIn"), m_fadeIn}, {QStringLiteral("fadeOut"), m_fadeOut},
                       {QStringLiteral("media"), media}, {QStringLiteral("clips"), clips},
                       {QStringLiteral("texts"), texts}, {QStringLiteral("music"), music}, {QStringLiteral("overlays"), overlays}};
}

void Project::fromJson(const QJsonObject &o)
{
    m_name = o.value(QLatin1String("name")).toString();
    m_format = o.value(QLatin1String("format")).toString(QStringLiteral("9:16"));
    m_fadeIn = o.value(QLatin1String("fadeIn")).toBool();
    m_fadeOut = o.value(QLatin1String("fadeOut")).toBool();
    m_media.clear();
    m_clips.clear();
    m_texts.clear();
    m_music.clear();
    m_overlays.clear();
    for (const QJsonValue &v : o.value(QLatin1String("media")).toArray()) {
        const QJsonObject m = v.toObject();
        Media x;
        x.path = m.value(QLatin1String("path")).toString();
        x.kind = m.value(QLatin1String("kind")).toString();
        x.name = QFileInfo(x.path).completeBaseName();
        x.frames = m.value(QLatin1String("frames")).toInt();
        x.w = m.value(QLatin1String("w")).toInt();
        x.h = m.value(QLatin1String("h")).toInt();
        x.audio = m.value(QLatin1String("audio")).toBool();
        m_media << x;
    }
    for (const QJsonValue &v : o.value(QLatin1String("clips")).toArray()) {
        const QJsonObject m = v.toObject();
        Clip c;
        c.id = m.value(QLatin1String("id")).toString();
        c.path = m.value(QLatin1String("path")).toString();
        c.kind = m.value(QLatin1String("kind")).toString();
        c.name = QFileInfo(c.path).completeBaseName();
        c.in = m.value(QLatin1String("in")).toInt();
        c.out = m.value(QLatin1String("out")).toInt();
        c.speed = m.value(QLatin1String("speed")).toDouble(1);
        c.volume = m.value(QLatin1String("volume")).toDouble(1);
        c.fill = m.value(QLatin1String("fill")).toBool(true);
        c.fade = m.value(QLatin1String("fade")).toInt();
        c.srcFrames = m.value(QLatin1String("srcFrames")).toInt();
        c.look = m.value(QLatin1String("look")).toString();
        c.brightness = m.value(QLatin1String("brightness")).toDouble(0);
        c.contrast = m.value(QLatin1String("contrast")).toDouble(1);
        c.saturation = m.value(QLatin1String("saturation")).toDouble(1);
        c.blurBg = m.value(QLatin1String("blurBg")).toBool();
        c.flip = m.value(QLatin1String("flip")).toBool();
        c.motion = m.value(QLatin1String("motion")).toString();
        c.trans = m.value(QLatin1String("trans")).toString(QStringLiteral("fade"));
        m_clips << c;
    }
    for (const QJsonValue &v : o.value(QLatin1String("texts")).toArray()) {
        const QJsonObject m = v.toObject();
        Text t;
        t.id = m.value(QLatin1String("id")).toString();
        t.text = m.value(QLatin1String("text")).toString();
        t.style = m.value(QLatin1String("style")).toString();
        t.anim = m.value(QLatin1String("anim")).toString(QStringLiteral("brak"));
        t.start = m.value(QLatin1String("start")).toInt();
        t.length = m.value(QLatin1String("length")).toInt();
        t.caption = m.value(QLatin1String("caption")).toBool();
        t.x = m.value(QLatin1String("x")).toDouble(-1);
        t.y = m.value(QLatin1String("y")).toDouble(-1);
        t.scale = m.value(QLatin1String("scale")).toDouble(1);
        t.color = m.value(QLatin1String("color")).toString();
        m_texts << t;
    }
    for (const QJsonValue &v : o.value(QLatin1String("overlays")).toArray()) {
        const QJsonObject m = v.toObject();
        Overlay n;
        n.id = m.value(QLatin1String("id")).toString();
        n.path = m.value(QLatin1String("path")).toString();
        n.kind = m.value(QLatin1String("kind")).toString();
        n.name = QFileInfo(n.path).completeBaseName();
        n.start = m.value(QLatin1String("start")).toInt();
        n.in = m.value(QLatin1String("in")).toInt();
        n.out = m.value(QLatin1String("out")).toInt();
        n.srcFrames = m.value(QLatin1String("srcFrames")).toInt();
        n.aspect = m.value(QLatin1String("aspect")).toDouble(1);
        n.x = m.value(QLatin1String("x")).toDouble(50);
        n.y = m.value(QLatin1String("y")).toDouble(32);
        n.scale = m.value(QLatin1String("scale")).toDouble(0.5);
        n.rotation = m.value(QLatin1String("rotation")).toDouble();
        n.opacity = m.value(QLatin1String("opacity")).toDouble(1);
        n.volume = m.value(QLatin1String("volume")).toDouble(1);
        n.shape = m.value(QLatin1String("shape")).toString(QStringLiteral("rect"));
        n.chroma = m.value(QLatin1String("chroma")).toBool();
        n.key = m.value(QLatin1String("key")).toString(QStringLiteral("#00B140"));
        n.variance = m.value(QLatin1String("variance")).toDouble(0.25);
        n.anim = m.value(QLatin1String("anim")).toString(QStringLiteral("brak"));
        m_overlays << n;
    }
    for (const QJsonValue &v : o.value(QLatin1String("music")).toArray()) {
        const QJsonObject m = v.toObject();
        Music x;
        x.id = m.value(QLatin1String("id")).toString();
        x.path = m.value(QLatin1String("path")).toString();
        x.name = QFileInfo(x.path).completeBaseName();
        x.start = m.value(QLatin1String("start")).toInt();
        x.in = m.value(QLatin1String("in")).toInt();
        x.out = m.value(QLatin1String("out")).toInt();
        x.srcFrames = m.value(QLatin1String("srcFrames")).toInt();
        x.volume = m.value(QLatin1String("volume")).toDouble(0.8);
        x.fadeOut = m.value(QLatin1String("fadeOut")).toBool(true);
        m_music << x;
    }
}

// ——— Zmiany i cofanie ———

void Project::snapshot(const QString &mergeKey)
{
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    // Kolejne ruchy tego samego suwaka (ta sama właściwość w ciągu 1,5 s) to jeden krok cofania
    if (!mergeKey.isEmpty() && mergeKey == m_lastKey && now - m_lastKeyTime < 1500) {
        m_lastKeyTime = now;
        return;
    }
    m_lastKey = mergeKey;
    m_lastKeyTime = now;
    m_undo << toJson();
    if (m_undo.size() > 100)
        m_undo.removeFirst();
    m_redo.clear();
}

void Project::commit()
{
    layout();
    ++m_revision;
    Q_EMIT changed();
    m_saveTimer.start();
}

void Project::undo()
{
    if (m_undo.isEmpty())
        return;
    m_redo << toJson();
    fromJson(m_undo.takeLast());
    m_lastKey.clear();
    commit();
}

void Project::redo()
{
    if (m_redo.isEmpty())
        return;
    m_undo << toJson();
    fromJson(m_redo.takeLast());
    m_lastKey.clear();
    commit();
}

int Project::clipLength(const Clip &c)
{
    return qMax(1, qRound((c.out - c.in + 1) / c.speed));
}

void Project::layout()
{
    int pos = 0, end = 0;
    for (int i = 0; i < m_clips.size(); ++i) {
        Clip &c = m_clips[i];
        c.length = clipLength(c);
        if (i == 0) {
            c.fade = 0;
        } else {
            // Przenikanie najwyżej przez połowę krótszego z sąsiadów (i z zapasem na przenikanie po drugiej stronie)
            const Clip &p = m_clips.at(i - 1);
            c.fade = qBound(0, c.fade, qMin(p.length - p.fade, c.length) / 2);
            pos -= c.fade;
        }
        c.start = pos;
        pos += c.length;
    }
    end = pos;
    for (const Text &t : m_texts)
        end = qMax(end, t.start + t.length);
    for (const Music &m : m_music)
        end = qMax(end, m.start + m.out - m.in + 1);
    for (const Overlay &o : m_overlays)
        end = qMax(end, o.start + o.out - o.in + 1);
    m_duration = end;
}

Project::Clip *Project::clip(const QString &id)
{
    for (Clip &c : m_clips)
        if (c.id == id)
            return &c;
    return nullptr;
}

Project::Text *Project::text(const QString &id)
{
    for (Text &t : m_texts)
        if (t.id == id)
            return &t;
    return nullptr;
}

Project::Overlay *Project::overlay(const QString &id)
{
    for (Overlay &o : m_overlays)
        if (o.id == id)
            return &o;
    return nullptr;
}

Project::Music *Project::track(const QString &id)
{
    for (Music &m : m_music)
        if (m.id == id)
            return &m;
    return nullptr;
}

QString Project::kindOf(const QString &id) const
{
    auto *self = const_cast<Project *>(this);
    if (self->clip(id))
        return QStringLiteral("clip");
    if (self->text(id))
        return QStringLiteral("text");
    if (self->track(id))
        return QStringLiteral("music");
    if (self->overlay(id))
        return QStringLiteral("overlay");
    return QString();
}

QVariantMap Project::item(const QString &id) const
{
    for (const QVariantList &l : {clips(), texts(), music(), overlays()})
        for (const QVariant &v : l)
            if (v.toMap().value(QStringLiteral("id")).toString() == id)
                return v.toMap();
    return {};
}

int Project::clipIndex(const QString &id) const
{
    for (int i = 0; i < m_clips.size(); ++i)
        if (m_clips.at(i).id == id)
            return i;
    return -1;
}

QString Project::clipAt(int frame) const
{
    for (int i = m_clips.size() - 1; i >= 0; --i)
        if (frame >= m_clips.at(i).start && frame < m_clips.at(i).start + m_clips.at(i).length)
            return m_clips.at(i).id;
    return QString();
}

QString Project::itemAt(const QString &trackName, int frame) const
{
    if (trackName == QLatin1String("text")) {
        for (const Text &t : m_texts)
            if (frame >= t.start && frame < t.start + t.length)
                return t.id;
    } else if (trackName == QLatin1String("overlay")) {
        for (const Overlay &o : m_overlays)
            if (frame >= o.start && frame <= o.start + o.out - o.in)
                return o.id;
    } else if (trackName == QLatin1String("music")) {
        for (const Music &m : m_music)
            if (frame >= m.start && frame <= m.start + m.out - m.in)
                return m.id;
    } else {
        return clipAt(frame);
    }
    return QString();
}

// ——— Import ———

const Project::Media *Project::probe(const QString &path)
{
    for (const Media &m : std::as_const(m_media))
        if (m.path == path)
            return &m;
    static QList<Media> cache;        // zbadane wcześniej (np. przy zgadywaniu formatu)
    for (const Media &m : std::as_const(cache))
        if (m.path == path)
            return &m;
    const QFileInfo fi(path);
    if (!fi.isFile())
        return nullptr;
    Media m;
    m.path = path;
    m.name = fi.completeBaseName();
    const QString ext = fi.suffix().toLower();
    if (imageExt.contains(ext)) {
        QImageReader r(path);
        r.setAutoTransform(true);
        const QSize s = r.size();
        if (!s.isValid() && !r.canRead())
            return nullptr;
        m.kind = QStringLiteral("image");
        m.w = s.width();
        m.h = s.height();
        m.frames = 0;
    } else {
        Mlt::Producer p(probeProfile(), nullptr, path.toUtf8().constData());
        if (!p.is_valid())
            return nullptr;
        m.frames = p.get_length();
        const int vi = p.get_int("video_index");
        const int ai = p.get_int("audio_index");
        m.audio = ai >= 0;
        const bool video = vi >= 0 && !audioExt.contains(ext)
                           && QString::fromUtf8(p.get(QStringLiteral("meta.media.%1.codec.name").arg(vi).toUtf8().constData())) != QLatin1String("mjpeg");
        if (video) {
            m.kind = QStringLiteral("video");
            m.w = p.get_int(QStringLiteral("meta.media.%1.codec.width").arg(vi).toUtf8().constData());
            m.h = p.get_int(QStringLiteral("meta.media.%1.codec.height").arg(vi).toUtf8().constData());
            if (m.w <= 0) { m.w = p.get_int("meta.media.width"); m.h = p.get_int("meta.media.height"); }
            // Filmy z telefonu bywają nagrane poziomo z informacją o obrocie
            const int rot = qAbs(p.get_int(QStringLiteral("meta.media.%1.codec.rotate").arg(vi).toUtf8().constData())) % 360;
            if (rot == 90 || rot == 270)
                std::swap(m.w, m.h);
        } else if (m.audio) {
            m.kind = QStringLiteral("audio");
        } else {
            return nullptr;
        }
        if (m.frames <= 1)
            return nullptr;
    }
    cache << m;
    return &cache.last();
}

int Project::importFiles(const QStringList &pathsOrUrls, int atFrame)
{
    if (m_id.isEmpty())
        return 0;
    QList<Media> found;
    QStringList bad;
    for (const QString &s : pathsOrUrls) {
        const QString path = toPath(s);
        const Media *m = probe(path);
        if (m)
            found << *m;
        else
            bad << QFileInfo(path).fileName();
    }
    if (!bad.isEmpty())
        Q_EMIT message(bad.size() == 1 ? QStringLiteral("Nie można otworzyć pliku „%1”").arg(bad.first())
                                       : QStringLiteral("Nie można otworzyć %1 plików").arg(bad.size()));
    if (found.isEmpty())
        return 0;
    snapshot();
    // Miejsce na ścieżce wideo: granica klipów najbliższa wskazanej klatce (albo koniec)
    int index = m_clips.size();
    if (atFrame >= 0) {
        index = 0;
        while (index < m_clips.size() && m_clips.at(index).start + m_clips.at(index).length / 2 < atFrame)
            ++index;
    }
    int musicAt = atFrame;
    if (musicAt < 0) {
        musicAt = 0;
        for (const Music &x : std::as_const(m_music))
            musicAt = qMax(musicAt, x.start + x.out - x.in + 1);
    }
    // Muzyka w tle kończy się razem z filmem (dłuższy utwór przycinamy — można go potem wydłużyć krawędzią)
    int videoEnd = 0;
    for (const Clip &c : std::as_const(m_clips))
        videoEnd = qMax(videoEnd, c.start + clipLength(c));
    for (const Media &m : std::as_const(found))
        if (m.kind != QLatin1String("audio"))
            videoEnd += m.kind == QLatin1String("image") ? ImageFrames : m.frames;
    for (const Media &m : std::as_const(found)) {
        bool known = false;
        for (const Media &x : std::as_const(m_media))
            known |= x.path == m.path;
        if (!known)
            m_media << m;
        if (m.kind == QLatin1String("audio")) {
            Music x;
            x.id = newId();
            x.path = m.path;
            x.name = m.name;
            x.start = musicAt;
            x.in = 0;
            x.out = m.frames - 1;
            if (videoEnd - musicAt >= 2 * Fps)
                x.out = qMin(x.out, videoEnd - musicAt - 1);
            x.srcFrames = m.frames;
            m_music << x;
            musicAt += x.out + 1;
        } else {
            Clip c;
            c.id = newId();
            c.path = m.path;
            c.kind = m.kind;
            c.name = m.name;
            c.in = 0;
            c.out = (m.kind == QLatin1String("image") ? ImageFrames : m.frames) - 1;
            c.srcFrames = m.kind == QLatin1String("image") ? 0 : m.frames;
            m_clips.insert(index++, c);
        }
    }
    commit();
    return found.size();
}

QString Project::addFromMedia(const QString &path, int frame)
{
    const int before = m_clips.size() + m_music.size();
    importFiles({path}, frame);
    if (m_clips.size() + m_music.size() == before)
        return QString();
    // Nowy element to ten, którego nie było — najprościej: ostatnio dodany id
    for (const Clip &c : std::as_const(m_clips))
        if (c.path == path && clipAt(qMax(0, frame)) == c.id)
            return c.id;
    return QString();
}

QString Project::addOverlay(const QString &pathOrUrl, int frame)
{
    if (m_id.isEmpty())
        return QString();
    const Media *m = probe(toPath(pathOrUrl));
    if (!m || m->kind == QLatin1String("audio")) {
        Q_EMIT message(m ? QStringLiteral("Na nakładkę nadaje się film albo zdjęcie") : QStringLiteral("Nie można otworzyć pliku"));
        return QString();
    }
    const Media media = *m;
    snapshot();
    bool known = false;
    for (const Media &x : std::as_const(m_media))
        known |= x.path == media.path;
    if (!known)
        m_media << media;
    Overlay o;
    o.id = newId();
    o.path = media.path;
    o.kind = media.kind;
    o.name = media.name;
    o.start = qMax(0, frame);
    o.srcFrames = media.kind == QLatin1String("image") ? 0 : media.frames;
    o.out = (media.kind == QLatin1String("image") ? ImageFrames : media.frames) - 1;
    o.aspect = media.w > 0 && media.h > 0 ? double(media.w) / media.h : 1;
    // Zdjęcie (naklejka) mniejsze i wyżej, film jako „okienko” w rogu
    if (media.kind == QLatin1String("image")) {
        o.scale = 0.4;
        o.x = 50;
        o.y = 30;
    } else {
        o.scale = 0.42;
        o.x = 72;
        o.y = 22;
        o.shape = QStringLiteral("rounded");
    }
    m_overlays << o;
    commit();
    return o.id;
}

QString Project::addText(int frame, const QString &str)
{
    if (m_id.isEmpty())
        return QString();
    snapshot();
    Text t;
    t.id = newId();
    t.text = str.isEmpty() ? QStringLiteral("Twój tekst") : str;
    t.style = QStringLiteral("klasyczny");
    t.start = qMax(0, frame);
    t.length = TextFrames;
    m_texts << t;
    commit();
    return t.id;
}

// ——— Edycja ———

void Project::trim(const QString &id, int ds, int de)
{
    if (ds == 0 && de == 0)
        return;
    if (Clip *c = clip(id)) {
        snapshot();
        if (c->kind == QLatin1String("image")) {
            c->out = qMax(MinFrames - 1, c->out + de - ds);
        } else {
            int in = c->in + qRound(ds * c->speed);
            int out = c->out + qRound(de * c->speed);
            in = qBound(0, in, c->out - MinFrames);
            out = qBound(in + MinFrames, out, c->srcFrames - 1);
            c->in = in;
            c->out = out;
        }
    } else if (Text *t = text(id)) {
        snapshot();
        const int end = t->start + t->length + de;
        t->start = qBound(0, t->start + ds, end - MinFrames);
        t->length = qMax(MinFrames, end - t->start);
    } else if (Music *m = track(id)) {
        snapshot();
        int in = m->in + ds;
        if (in < 0) { ds -= in; in = 0; }
        if (m->start + ds < 0) { in -= m->start + ds; ds = -m->start; }
        in = qMin(in, m->out - MinFrames);
        m->start += in - m->in;
        m->in = in;
        m->out = qBound(m->in + MinFrames, m->out + de, m->srcFrames - 1);
    } else if (Overlay *o = overlay(id)) {
        snapshot();
        if (o->srcFrames <= 0) {          // zdjęcie: zmienia się tylko początek i długość
            const int end = o->start + o->out - o->in + 1 + de;
            o->start = qBound(0, o->start + ds, end - MinFrames);
            o->in = 0;
            o->out = qMax(MinFrames, end - o->start) - 1;
        } else {
            int in = o->in + ds;
            if (in < 0) { ds -= in; in = 0; }
            if (o->start + ds < 0) { in -= o->start + ds; ds = -o->start; }
            in = qMin(in, o->out - MinFrames);
            o->start += in - o->in;
            o->in = in;
            o->out = qBound(o->in + MinFrames, o->out + de, o->srcFrames - 1);
        }
    } else {
        return;
    }
    commit();
}

void Project::moveClip(const QString &id, int index)
{
    const int from = clipIndex(id);
    if (from < 0)
        return;
    index = qBound(0, index, m_clips.size() - 1);
    if (index == from)
        return;
    snapshot();
    m_clips.move(from, index);
    commit();
}

void Project::moveItem(const QString &id, int start)
{
    start = qMax(0, start);
    if (Text *t = text(id)) {
        if (t->start == start)
            return;
        snapshot();
        t->start = start;
    } else if (Music *m = track(id)) {
        if (m->start == start)
            return;
        snapshot();
        m->start = start;
    } else if (Overlay *o = overlay(id)) {
        if (o->start == start)
            return;
        snapshot();
        o->start = start;
    } else {
        return;
    }
    commit();
}

QString Project::split(const QString &id, int frame)
{
    const QString nid = newId();
    if (Clip *c = clip(id)) {
        const int local = frame - c->start;
        if (local < 3 || local > c->length - 3)
            return QString();
        snapshot();
        Clip second = *c;
        second.id = nid;
        second.fade = 0;
        if (c->kind == QLatin1String("image")) {
            second.out = c->length - local - 1;
            c->out = local - 1;
        } else {
            const int cut = c->in + qRound(local * c->speed);
            second.in = cut;
            c->out = cut - 1;
        }
        m_clips.insert(clipIndex(id) + 1, second);
    } else if (Text *t = text(id)) {
        const int local = frame - t->start;
        if (local < 3 || local > t->length - 3)
            return QString();
        snapshot();
        Text second = *t;
        second.id = nid;
        second.start = frame;
        second.length = t->length - local;
        t->length = local;
        m_texts << second;
    } else if (Music *m = track(id)) {
        const int local = frame - m->start;
        if (local < 3 || local > m->out - m->in - 3)
            return QString();
        snapshot();
        Music second = *m;
        second.id = nid;
        second.start = frame;
        second.in = m->in + local;
        m->out = m->in + local - 1;
        m->fadeOut = false;
        m_music << second;
    } else if (Overlay *o = overlay(id)) {
        const int local = frame - o->start;
        if (local < 3 || local > o->out - o->in - 3)
            return QString();
        snapshot();
        Overlay second = *o;
        second.id = nid;
        second.start = frame;
        second.in = o->srcFrames > 0 ? o->in + local : 0;
        second.out = o->srcFrames > 0 ? o->out : o->out - local;
        o->out = o->in + local - 1;
        m_overlays << second;
    } else {
        return QString();
    }
    commit();
    return nid;
}

void Project::remove(const QString &id)
{
    if (kindOf(id).isEmpty())
        return;
    snapshot();
    m_clips.removeIf([&](const Clip &c) { return c.id == id; });
    m_texts.removeIf([&](const Text &t) { return t.id == id; });
    m_music.removeIf([&](const Music &m) { return m.id == id; });
    m_overlays.removeIf([&](const Overlay &o) { return o.id == id; });
    commit();
}

void Project::setValue(const QString &id, const QString &key, const QVariant &value)
{
    const QString merge = id + QLatin1Char('/') + key;
    if (Clip *c = clip(id)) {
        snapshot(merge);
        if (key == QLatin1String("volume"))
            c->volume = qBound(0.0, value.toDouble(), 2.0);
        else if (key == QLatin1String("speed"))
            c->speed = qBound(0.25, value.toDouble(), 4.0);
        else if (key == QLatin1String("fill"))
            c->fill = value.toBool();
        else if (key == QLatin1String("fit")) {
            c->fill = value.toString() == QLatin1String("fill");
            c->blurBg = value.toString() == QLatin1String("blur");
        } else if (key == QLatin1String("flip"))
            c->flip = value.toBool();
        else if (key == QLatin1String("motion"))
            c->motion = value.toString();
        else if (key == QLatin1String("trans")) {
            c->trans = value.toString();
            if (c->fade <= 0)
                c->fade = Fps / 2;        // wybór przejścia od razu je włącza
        }
        else if (key == QLatin1String("fade"))
            c->fade = qMax(0, value.toInt());
        else if (key == QLatin1String("look"))
            c->look = value.toString();
        else if (key == QLatin1String("resetLook")) {
            c->look.clear();
            c->brightness = 0;
            c->contrast = c->saturation = 1;
        }
        else if (key == QLatin1String("brightness"))
            c->brightness = qBound(-0.5, value.toDouble(), 0.5);
        else if (key == QLatin1String("contrast"))
            c->contrast = qBound(0.3, value.toDouble(), 2.0);
        else if (key == QLatin1String("saturation"))
            c->saturation = qBound(0.0, value.toDouble(), 2.5);
    } else if (Text *t = text(id)) {
        snapshot(merge);
        if (key == QLatin1String("text"))
            t->text = value.toString();
        else if (key == QLatin1String("style"))
            t->style = value.toString();
        else if (key == QLatin1String("anim"))
            t->anim = value.toString();
        else if (key == QLatin1String("pos")) {           // {x, y} w % kadru
            const QVariantMap p = value.toMap();
            t->x = qBound(5.0, p.value(QStringLiteral("x")).toDouble(), 95.0);
            t->y = qBound(5.0, p.value(QStringLiteral("y")).toDouble(), 95.0);
        } else if (key == QLatin1String("scale"))
            t->scale = qBound(0.4, value.toDouble(), 3.0);
        else if (key == QLatin1String("color"))
            t->color = value.toString();
        else if (key == QLatin1String("resetPos")) {
            t->x = t->y = -1;
            t->scale = 1;
        }
    } else if (Music *m = track(id)) {
        snapshot(merge);
        if (key == QLatin1String("volume"))
            m->volume = qBound(0.0, value.toDouble(), 2.0);
        else if (key == QLatin1String("fadeOut"))
            m->fadeOut = value.toBool();
    } else if (Overlay *o = overlay(id)) {
        snapshot(merge);
        if (key == QLatin1String("pos")) {
            const QVariantMap p = value.toMap();
            o->x = qBound(-20.0, p.value(QStringLiteral("x")).toDouble(), 120.0);
            o->y = qBound(-20.0, p.value(QStringLiteral("y")).toDouble(), 120.0);
        } else if (key == QLatin1String("scale"))
            o->scale = qBound(0.05, value.toDouble(), 2.0);
        else if (key == QLatin1String("rotation"))
            o->rotation = qBound(-180.0, value.toDouble(), 180.0);
        else if (key == QLatin1String("opacity"))
            o->opacity = qBound(0.05, value.toDouble(), 1.0);
        else if (key == QLatin1String("volume"))
            o->volume = qBound(0.0, value.toDouble(), 2.0);
        else if (key == QLatin1String("shape"))
            o->shape = value.toString();
        else if (key == QLatin1String("chroma"))
            o->chroma = value.toBool();
        else if (key == QLatin1String("key"))
            o->key = value.toString();
        else if (key == QLatin1String("variance"))
            o->variance = qBound(0.02, value.toDouble(), 0.6);
        else if (key == QLatin1String("anim"))
            o->anim = value.toString();
        else if (key == QLatin1String("full")) {      // na cały kadr
            o->x = o->y = 50;
            o->scale = 1;
            o->rotation = 0;
        }
    } else {
        return;
    }
    commit();
}

int Project::setCaptions(const QVariantList &items, const QString &style)
{
    snapshot();
    m_texts.removeIf([](const Text &t) { return t.caption; });
    QList<QVariantMap> list;
    for (const QVariant &v : items)
        list << v.toMap();
    std::sort(list.begin(), list.end(), [](const QVariantMap &a, const QVariantMap &b) {
        return a.value(QStringLiteral("start")).toInt() < b.value(QStringLiteral("start")).toInt();
    });
    int added = 0;
    for (int i = 0; i < list.size(); ++i) {
        Text t;
        t.id = newId();
        t.text = list.at(i).value(QStringLiteral("text")).toString();
        t.style = style.isEmpty() ? QStringLiteral("zolty") : style;
        t.anim = QStringLiteral("brak");
        t.caption = true;
        t.start = list.at(i).value(QStringLiteral("start")).toInt();
        // Każdy napis widać co najmniej 0,6 s, ale nie dłużej niż do następnego
        int end = qMax(list.at(i).value(QStringLiteral("end")).toInt(), t.start + Fps * 6 / 10);
        if (i + 1 < list.size())
            end = qMin(end, list.at(i + 1).value(QStringLiteral("start")).toInt());
        t.length = end - t.start;
        if (t.length < 3)
            continue;
        m_texts << t;
        ++added;
    }
    commit();
    return added;
}

void Project::applyTransitionToAll(const QString &fromId)
{
    const Clip *from = clip(fromId);
    if (!from || m_clips.size() < 2)
        return;
    const QString trans = from->trans;
    const int fade = from->fade > 0 ? from->fade : Fps / 2;
    snapshot();
    for (int i = 1; i < m_clips.size(); ++i) {
        m_clips[i].trans = trans;
        m_clips[i].fade = fade;
    }
    commit();
}

void Project::setOption(const QString &key, const QVariant &value)
{
    snapshot();
    if (key == QLatin1String("format")) {
        const QString f = value.toString();
        if (f == QLatin1String("9:16") || f == QLatin1String("16:9") || f == QLatin1String("1:1"))
            m_format = f;
    } else if (key == QLatin1String("fadeIn"))
        m_fadeIn = value.toBool();
    else if (key == QLatin1String("fadeOut"))
        m_fadeOut = value.toBool();
    commit();
}

// ——— Opis MLT ———

QString Project::xml(int W, int H) const
{
    QString out;
    QXmlStreamWriter x(&out);
    x.setAutoFormatting(true);
    auto prop = [&x](const QString &name, const QString &value) {
        x.writeStartElement(QStringLiteral("property"));
        x.writeAttribute(QStringLiteral("name"), name);
        x.writeCharacters(value);
        x.writeEndElement();
    };
    auto num = [](double v) { return QString::number(v, 'g', 8); };
    auto filter = [&](const QString &service, const QList<QPair<QString, QString>> &props, int in = -1, int outF = -1) {
        x.writeStartElement(QStringLiteral("filter"));
        if (in >= 0) {
            x.writeAttribute(QStringLiteral("in"), QString::number(in));
            x.writeAttribute(QStringLiteral("out"), QString::number(outF));
        }
        prop(QStringLiteral("mlt_service"), service);
        for (const auto &p : props)
            prop(p.first, p.second);
        x.writeEndElement();
    };
    const int total = qMax(1, m_duration);

    x.writeStartDocument();
    x.writeStartElement(QStringLiteral("mlt"));
    x.writeAttribute(QStringLiteral("LC_NUMERIC"), QStringLiteral("C"));
    x.writeAttribute(QStringLiteral("title"), m_name);
    x.writeStartElement(QStringLiteral("profile"));
    const int g = std::gcd(W, H);
    for (const auto &[k, v] : QList<QPair<QString, int>>{{QStringLiteral("width"), W}, {QStringLiteral("height"), H},
                                                           {QStringLiteral("frame_rate_num"), Fps}, {QStringLiteral("frame_rate_den"), 1},
                                                           {QStringLiteral("progressive"), 1}, {QStringLiteral("sample_aspect_num"), 1},
                                                           {QStringLiteral("sample_aspect_den"), 1}, {QStringLiteral("display_aspect_num"), W / g},
                                                           {QStringLiteral("display_aspect_den"), H / g}, {QStringLiteral("colorspace"), 709}})
        x.writeAttribute(k, QString::number(v));
    x.writeEndElement();

    // Tło
    x.writeStartElement(QStringLiteral("producer"));
    x.writeAttribute(QStringLiteral("id"), QStringLiteral("tlo"));
    x.writeAttribute(QStringLiteral("in"), QStringLiteral("0"));
    x.writeAttribute(QStringLiteral("out"), QString::number(total - 1));
    prop(QStringLiteral("mlt_service"), QStringLiteral("color"));
    prop(QStringLiteral("resource"), QStringLiteral("#FF000000"));
    prop(QStringLiteral("length"), QString::number(total));
    x.writeEndElement();

    // Kolorowe plansze do przejść (przez czerń, błysk, tło przesunięć)
    for (const auto &[id, colour] : QList<QPair<QString, QString>>{{QStringLiteral("czern"), QStringLiteral("#FF000000")},
                                                                     {QStringLiteral("biel"), QStringLiteral("#FFFFFFFF")}}) {
        x.writeStartElement(QStringLiteral("producer"));
        x.writeAttribute(QStringLiteral("id"), id);
        x.writeAttribute(QStringLiteral("in"), QStringLiteral("0"));
        x.writeAttribute(QStringLiteral("out"), QStringLiteral("99999"));
        prop(QStringLiteral("mlt_service"), QStringLiteral("color"));
        prop(QStringLiteral("resource"), colour);
        prop(QStringLiteral("length"), QStringLiteral("100000"));
        x.writeEndElement();
    }
    auto rectPx = [&](double fx, double fy, double fw, double fh, double opacity = 1) {
        return QStringLiteral("%1 %2 %3 %4 %5").arg(qRound(fx * W)).arg(qRound(fy * H)).arg(qRound(fw * W)).arg(qRound(fh * H)).arg(num(opacity));
    };

    // Klipy (każdy jako osobne źródło; prędkość przez timewarp, wypełnienie kadru przez crop,
    // rozmyte tło jako mały tractor: rozmyta kopia pod klipem zmieszczonym w kadrze)
    QList<int> warpIn;
    for (int i = 0; i < m_clips.size(); ++i) {
        const Clip &c = m_clips.at(i);
        const bool image = c.kind == QLatin1String("image");
        const bool warp = !image && !qFuzzyCompare(c.speed, 1.0);
        const int len = image ? 100000 : qMax(1, int(c.srcFrames / (warp ? c.speed : 1.0)));
        const int wi = image ? 0 : qRound(c.in / (warp ? c.speed : 1.0));
        warpIn << wi;
        // Ruch kadru: klatki kluczowe w pozycjach źródła (od wi do wi + długość)
        QString motion;
        const int a = wi, e = wi + c.length - 1;
        if (c.motion == QLatin1String("zoomin"))
            motion = QStringLiteral("%1=%2;%3=%4").arg(a).arg(rectPx(0, 0, 1, 1)).arg(e).arg(rectPx(-0.08, -0.08, 1.16, 1.16));
        else if (c.motion == QLatin1String("zoomout"))
            motion = QStringLiteral("%1=%2;%3=%4").arg(a).arg(rectPx(-0.08, -0.08, 1.16, 1.16)).arg(e).arg(rectPx(0, 0, 1, 1));
        else if (c.motion == QLatin1String("panleft"))
            motion = QStringLiteral("%1=%2;%3=%4").arg(a).arg(rectPx(0, -0.08, 1.16, 1.16)).arg(e).arg(rectPx(-0.16, -0.08, 1.16, 1.16));
        else if (c.motion == QLatin1String("panright"))
            motion = QStringLiteral("%1=%2;%3=%4").arg(a).arg(rectPx(-0.16, -0.08, 1.16, 1.16)).arg(e).arg(rectPx(0, -0.08, 1.16, 1.16));
        else if (c.motion == QLatin1String("pulse") || c.motion == QLatin1String("shake")) {
            QStringList keys;
            const bool pulse = c.motion == QLatin1String("pulse");
            const int step = pulse ? Fps / 4 : 2;
            quint32 seed = 12345;
            for (int f = a, k = 0; f <= e; f += step, ++k) {
                if (pulse) {
                    const double z = k % 2 ? 0.05 : 0;          // uderzenie co pół sekundy
                    keys << QStringLiteral("%1=%2").arg(f).arg(rectPx(-z / 2, -z / 2, 1 + z, 1 + z));
                } else {
                    seed = seed * 1103515245 + 12345;
                    const double dx = ((seed >> 16) % 100) / 100.0 * 0.03 - 0.015;
                    seed = seed * 1103515245 + 12345;
                    const double dy = ((seed >> 16) % 100) / 100.0 * 0.03 - 0.015;
                    keys << QStringLiteral("%1=%2").arg(f).arg(rectPx(-0.03 + dx, -0.03 + dy, 1.06, 1.06));
                }
            }
            motion = keys.join(QLatin1Char(';'));
        }
        auto clipFilters = [&] {
            if (!motion.isEmpty())
                filter(QStringLiteral("affine"), {{QStringLiteral("transition.rect"), motion}, {QStringLiteral("transition.fill"), QStringLiteral("1")},
                                                  {QStringLiteral("transition.distort"), QStringLiteral("0")}});
            if (!image && !qFuzzyCompare(c.volume, 1.0))
                filter(QStringLiteral("volume"), {{QStringLiteral("gain"), num(c.volume)}});
        };
        auto source = [&](const QString &id, bool crop, bool blurred, bool effects, bool own = false) {
            x.writeStartElement(QStringLiteral("producer"));
            x.writeAttribute(QStringLiteral("id"), id);
            x.writeAttribute(QStringLiteral("in"), QStringLiteral("0"));
            x.writeAttribute(QStringLiteral("out"), QString::number(len - 1));
            if (warp) {
                prop(QStringLiteral("mlt_service"), QStringLiteral("timewarp"));
                prop(QStringLiteral("resource"), num(c.speed) + QLatin1Char(':') + c.path);
                prop(QStringLiteral("warp_pitch"), QStringLiteral("1"));
            } else {
                prop(QStringLiteral("resource"), c.path);
            }
            if (image) {
                prop(QStringLiteral("length"), QString::number(len));
                prop(QStringLiteral("ttl"), QStringLiteral("1"));
            }
            if (crop)
                filter(QStringLiteral("crop"), {{QStringLiteral("center"), QStringLiteral("1")}});
            if (blurred) {
                const QString radius = QString::number(qMax(4, W / 28));
                filter(QStringLiteral("box_blur"), {{QStringLiteral("hradius"), radius}, {QStringLiteral("vradius"), radius}});
                filter(QStringLiteral("brightness"), {{QStringLiteral("level"), QStringLiteral("0.8")}});
                filter(QStringLiteral("volume"), {{QStringLiteral("gain"), QStringLiteral("0")}});
            }
            if (effects) {
                for (const auto &f : lookFilters(c.look, c.brightness, c.contrast, c.saturation))
                    filter(f.first, f.second);
                if (c.flip)
                    filter(QStringLiteral("avfilter.hflip"), {});
            }
            if (own)
                clipFilters();
            x.writeEndElement();
        };
        const QString id = QStringLiteral("k%1").arg(i);
        if (c.blurBg) {
            source(id + QStringLiteral("t"), true, true, true);
            source(id + QStringLiteral("p"), false, false, true);
            x.writeStartElement(QStringLiteral("tractor"));
            x.writeAttribute(QStringLiteral("id"), id);
            x.writeAttribute(QStringLiteral("in"), QStringLiteral("0"));
            x.writeAttribute(QStringLiteral("out"), QString::number(len - 1));
            for (const QString &t : {id + QStringLiteral("t"), id + QStringLiteral("p")}) {
                x.writeStartElement(QStringLiteral("track"));
                x.writeAttribute(QStringLiteral("producer"), t);
                x.writeEndElement();
            }
            x.writeStartElement(QStringLiteral("transition"));
            prop(QStringLiteral("mlt_service"), QStringLiteral("affine"));
            prop(QStringLiteral("a_track"), QStringLiteral("0"));
            prop(QStringLiteral("b_track"), QStringLiteral("1"));
            prop(QStringLiteral("rect"), rectPx(0, 0, 1, 1));
            prop(QStringLiteral("fill"), QStringLiteral("1"));
            prop(QStringLiteral("distort"), QStringLiteral("0"));
            prop(QStringLiteral("always_active"), QStringLiteral("1"));
            x.writeEndElement();
            x.writeStartElement(QStringLiteral("transition"));
            prop(QStringLiteral("mlt_service"), QStringLiteral("mix"));
            prop(QStringLiteral("a_track"), QStringLiteral("0"));
            prop(QStringLiteral("b_track"), QStringLiteral("1"));
            prop(QStringLiteral("always_active"), QStringLiteral("1"));
            prop(QStringLiteral("sum"), QStringLiteral("1"));
            x.writeEndElement();
            clipFilters();
            x.writeEndElement();
        } else {
            source(id, c.fill, false, true, true);
        }
    }
    // Przejścia: mały tractor z końcówką poprzedniego i początkiem następnego klipu.
    // Ścieżki: A (koniec poprzedniego), B (początek następnego), czasem plansza; ruch przez affine,
    // obrót i błysk przez qtblend, kurtyna i koło przez luma z narysowanym obrazem.
    for (int i = 1; i < m_clips.size(); ++i) {
        const Clip &c = m_clips.at(i);
        const int f = c.fade;
        if (f <= 0)
            continue;
        const Clip &p = m_clips.at(i - 1);
        const int pEnd = warpIn.at(i - 1) + p.length - 1;
        struct Track { QString producer; int in, out; };
        const Track A{QStringLiteral("k%1").arg(i - 1), pEnd - f + 1, pEnd};
        const Track B{QStringLiteral("k%1").arg(i), warpIn.at(i), warpIn.at(i) + f - 1};
        const QString type = c.trans;
        const int mid = (f - 1) / 2, last = f - 1;
        QList<Track> tracks;
        struct Tr { QString service; int a, b; QList<QPair<QString, QString>> props; };
        QList<Tr> trs;
        QList<QPair<QString, QList<QPair<QString, QString>>>> filters;
        const auto full = rectPx(0, 0, 1, 1);
        auto anim = [&](const QString &from, const QString &to) { return QStringLiteral("0=%1;%2=%3").arg(from).arg(last).arg(to); };
        auto anim3 = [&](const QString &from, const QString &middle, const QString &to) {
            return QStringLiteral("0=%1;%2=%3;%4=%5").arg(from).arg(mid).arg(middle).arg(last).arg(to);
        };
        const QList<QPair<QString, QString>> crossMix = {{QStringLiteral("start"), QStringLiteral("0")}, {QStringLiteral("end"), QStringLiteral("1")}};
        const QList<QPair<QString, QString>> keep = {{QStringLiteral("fill"), QStringLiteral("1")}, {QStringLiteral("distort"), QStringLiteral("0")},
                                                     {QStringLiteral("always_active"), QStringLiteral("1")}};
        if (type == QLatin1String("black") || type == QLatin1String("white")) {
            tracks = {A, B, Track{type == QLatin1String("black") ? QStringLiteral("czern") : QStringLiteral("biel"), 0, last}};
            trs << Tr{QStringLiteral("luma"), 0, 1, {}}
                << Tr{QStringLiteral("qtblend"), 0, 2, {{QStringLiteral("rect"), anim3(rectPx(0, 0, 1, 1, 0), full, rectPx(0, 0, 1, 1, 0))}}}
                << Tr{QStringLiteral("mix"), 0, 1, crossMix};
        } else if (type == QLatin1String("pushleft") || type == QLatin1String("pushup") || type == QLatin1String("whip")) {
            const bool up = type == QLatin1String("pushup");
            tracks = {Track{QStringLiteral("czern"), 0, last}, A, B};
            auto r1 = up ? rectPx(0, -1, 1, 1) : rectPx(-1, 0, 1, 1);
            auto r2 = up ? rectPx(0, 1, 1, 1) : rectPx(1, 0, 1, 1);
            trs << Tr{QStringLiteral("affine"), 0, 1, keep + QList<QPair<QString, QString>>{{QStringLiteral("rect"), anim(full, r1)}}}
                << Tr{QStringLiteral("affine"), 0, 2, keep + QList<QPair<QString, QString>>{{QStringLiteral("rect"), anim(r2, full)}}}
                << Tr{QStringLiteral("mix"), 1, 2, crossMix}
                << Tr{QStringLiteral("mix"), 0, 1, {{QStringLiteral("always_active"), QStringLiteral("1")}, {QStringLiteral("sum"), QStringLiteral("1")}}};
            if (type == QLatin1String("whip")) {
                const QString r = QString::number(qMax(6, W / 12));
                filters << qMakePair(QStringLiteral("box_blur"), QList<QPair<QString, QString>>{
                    {QStringLiteral("hradius"), anim3(QStringLiteral("0"), r, QStringLiteral("0"))}, {QStringLiteral("vradius"), QStringLiteral("0")}});
            }
        } else if (type == QLatin1String("slide")) {
            tracks = {A, B};
            trs << Tr{QStringLiteral("affine"), 0, 1, keep + QList<QPair<QString, QString>>{{QStringLiteral("rect"), anim(rectPx(1, 0, 1, 1), full)}}}
                << Tr{QStringLiteral("mix"), 0, 1, crossMix};
        } else if (type == QLatin1String("zoomin")) {
            tracks = {B, A};          // poprzedni klip na wierzchu rośnie i znika
            trs << Tr{QStringLiteral("affine"), 0, 1, keep + QList<QPair<QString, QString>>{{QStringLiteral("rect"), anim(full, rectPx(-0.5, -0.5, 2, 2, 0))}}}
                << Tr{QStringLiteral("mix"), 0, 1, {{QStringLiteral("start"), QStringLiteral("1")}, {QStringLiteral("end"), QStringLiteral("0")}}};
        } else if (type == QLatin1String("zoomout")) {
            tracks = {A, B};
            trs << Tr{QStringLiteral("affine"), 0, 1, keep + QList<QPair<QString, QString>>{{QStringLiteral("rect"), anim(rectPx(-0.3, -0.3, 1.6, 1.6, 0), full)}}}
                << Tr{QStringLiteral("mix"), 0, 1, crossMix};
        } else if (type == QLatin1String("spin")) {
            tracks = {A, B};
            trs << Tr{QStringLiteral("qtblend"), 0, 1, {{QStringLiteral("rect"), anim(rectPx(0.3, 0.3, 0.4, 0.4, 0), full)},
                                                         {QStringLiteral("rotation"), anim(QStringLiteral("-180"), QStringLiteral("0"))}}}
                << Tr{QStringLiteral("mix"), 0, 1, crossMix};
        } else if (type == QLatin1String("wipe") || type == QLatin1String("circle")) {
            tracks = {A, B};
            trs << Tr{QStringLiteral("luma"), 0, 1, {{QStringLiteral("resource"), lumaFile(type == QLatin1String("wipe") ? QStringLiteral("wipe") : QStringLiteral("circle"), W, H)},
                                                      {QStringLiteral("softness"), QStringLiteral("0.12")}}}
                << Tr{QStringLiteral("mix"), 0, 1, crossMix};
        } else {          // przenikanie i rozmycie
            tracks = {A, B};
            trs << Tr{QStringLiteral("luma"), 0, 1, {}} << Tr{QStringLiteral("mix"), 0, 1, crossMix};
            if (type == QLatin1String("blur")) {
                const QString r = QString::number(qMax(4, W / 30));
                filters << qMakePair(QStringLiteral("box_blur"), QList<QPair<QString, QString>>{
                    {QStringLiteral("hradius"), anim3(QStringLiteral("0"), r, QStringLiteral("0"))}, {QStringLiteral("vradius"), anim3(QStringLiteral("0"), r, QStringLiteral("0"))}});
            }
        }
        x.writeStartElement(QStringLiteral("tractor"));
        x.writeAttribute(QStringLiteral("id"), QStringLiteral("p%1").arg(i));
        x.writeAttribute(QStringLiteral("in"), QStringLiteral("0"));
        x.writeAttribute(QStringLiteral("out"), QString::number(last));
        for (const Track &t : std::as_const(tracks)) {
            x.writeStartElement(QStringLiteral("track"));
            x.writeAttribute(QStringLiteral("producer"), t.producer);
            x.writeAttribute(QStringLiteral("in"), QString::number(t.in));
            x.writeAttribute(QStringLiteral("out"), QString::number(t.out));
            x.writeEndElement();
        }
        for (const Tr &t : std::as_const(trs)) {
            x.writeStartElement(QStringLiteral("transition"));
            x.writeAttribute(QStringLiteral("in"), QStringLiteral("0"));
            x.writeAttribute(QStringLiteral("out"), QString::number(last));
            prop(QStringLiteral("mlt_service"), t.service);
            prop(QStringLiteral("a_track"), QString::number(t.a));
            prop(QStringLiteral("b_track"), QString::number(t.b));
            for (const auto &pp : t.props)
                prop(pp.first, pp.second);
            x.writeEndElement();
        }
        for (const auto &fl : std::as_const(filters))
            filter(fl.first, fl.second);
        x.writeEndElement();
    }
    x.writeStartElement(QStringLiteral("playlist"));
    x.writeAttribute(QStringLiteral("id"), QStringLiteral("wideo"));
    for (int i = 0; i < m_clips.size(); ++i) {
        const Clip &c = m_clips.at(i);
        const int nextFade = i + 1 < m_clips.size() ? m_clips.at(i + 1).fade : 0;
        if (c.fade > 0) {
            x.writeStartElement(QStringLiteral("entry"));
            x.writeAttribute(QStringLiteral("producer"), QStringLiteral("p%1").arg(i));
            x.writeAttribute(QStringLiteral("in"), QStringLiteral("0"));
            x.writeAttribute(QStringLiteral("out"), QString::number(c.fade - 1));
            x.writeEndElement();
        }
        const int in = warpIn.at(i) + c.fade, outF = warpIn.at(i) + c.length - 1 - nextFade;
        if (outF >= in) {
            x.writeStartElement(QStringLiteral("entry"));
            x.writeAttribute(QStringLiteral("producer"), QStringLiteral("k%1").arg(i));
            x.writeAttribute(QStringLiteral("in"), QString::number(in));
            x.writeAttribute(QStringLiteral("out"), QString::number(outF));
            x.writeEndElement();
        }
    }
    x.writeEndElement();

    // Muzyka: każdy utwór na własnej ścieżce (mogą na siebie zachodzić)
    for (int i = 0; i < m_music.size(); ++i) {
        const Music &m = m_music.at(i);
        x.writeStartElement(QStringLiteral("producer"));
        x.writeAttribute(QStringLiteral("id"), QStringLiteral("m%1").arg(i));
        x.writeAttribute(QStringLiteral("in"), QStringLiteral("0"));
        x.writeAttribute(QStringLiteral("out"), QString::number(m.srcFrames - 1));
        prop(QStringLiteral("resource"), m.path);
        prop(QStringLiteral("video_index"), QStringLiteral("-1"));
        filter(QStringLiteral("volume"), {{QStringLiteral("gain"), num(m.volume)}});
        x.writeEndElement();
        x.writeStartElement(QStringLiteral("playlist"));
        x.writeAttribute(QStringLiteral("id"), QStringLiteral("muzyka%1").arg(i));
        if (m.start > 0) {
            x.writeStartElement(QStringLiteral("blank"));
            x.writeAttribute(QStringLiteral("length"), QString::number(m.start));
            x.writeEndElement();
        }
        x.writeStartElement(QStringLiteral("entry"));
        x.writeAttribute(QStringLiteral("producer"), QStringLiteral("m%1").arg(i));
        x.writeAttribute(QStringLiteral("in"), QString::number(m.in));
        x.writeAttribute(QStringLiteral("out"), QString::number(m.out));
        const int len = m.out - m.in + 1;
        if (m.fadeOut && len > 2 * Fps)          // łagodne wyciszenie przez ostatnią sekundę
            filter(QStringLiteral("volume"), {{QStringLiteral("gain"), QStringLiteral("1")}, {QStringLiteral("end"), QStringLiteral("0")}},
                   len - Fps, len - 1);
        x.writeEndElement();
        x.writeEndElement();
    }

    // Nakładki (druga ścieżka obrazu): każda na własnej ścieżce, nakładana przez affine
    // (położenie, wielkość, obrót, przezroczystość, animacja wejścia i wyjścia)
    QStringList overlayRects, overlayRotations;
    for (int i = 0; i < m_overlays.size(); ++i) {
        const Overlay &o = m_overlays.at(i);
        const bool image = o.kind == QLatin1String("image");
        const int len = o.out - o.in + 1;
        const bool circle = o.shape == QLatin1String("circle");
        x.writeStartElement(QStringLiteral("producer"));
        x.writeAttribute(QStringLiteral("id"), QStringLiteral("n%1").arg(i));
        x.writeAttribute(QStringLiteral("in"), QStringLiteral("0"));
        x.writeAttribute(QStringLiteral("out"), QString::number((image ? 100000 : o.srcFrames) - 1));
        prop(QStringLiteral("resource"), o.path);
        if (image) {
            prop(QStringLiteral("length"), QStringLiteral("100000"));
            prop(QStringLiteral("ttl"), QStringLiteral("1"));
        }
        if (o.chroma)
            filter(QStringLiteral("chroma"), {{QStringLiteral("key"), o.key}, {QStringLiteral("variance"), num(o.variance)}});
        if (circle) {
            // Koło na środku obrazu, o średnicy krótszego boku (radius 0,5 w qtcrop)
            filter(QStringLiteral("qtcrop"), {{QStringLiteral("rect"), QStringLiteral("0% 0% 100% 100%")}, {QStringLiteral("circle"), QStringLiteral("1")},
                                              {QStringLiteral("radius"), QStringLiteral("0.5")}, {QStringLiteral("color"), QStringLiteral("#00000000")}});
        } else if (o.shape == QLatin1String("rounded")) {
            filter(QStringLiteral("qtcrop"), {{QStringLiteral("rect"), QStringLiteral("0% 0% 100% 100%")}, {QStringLiteral("radius"), QStringLiteral("0.18")},
                                              {QStringLiteral("color"), QStringLiteral("#00000000")}});
        }
        if (!image && !qFuzzyCompare(o.volume, 1.0))
            filter(QStringLiteral("volume"), {{QStringLiteral("gain"), num(o.volume)}});
        x.writeEndElement();
        x.writeStartElement(QStringLiteral("playlist"));
        x.writeAttribute(QStringLiteral("id"), QStringLiteral("nakladka%1").arg(i));
        if (o.start > 0) {
            x.writeStartElement(QStringLiteral("blank"));
            x.writeAttribute(QStringLiteral("length"), QString::number(o.start));
            x.writeEndElement();
        }
        x.writeStartElement(QStringLiteral("entry"));
        x.writeAttribute(QStringLiteral("producer"), QStringLiteral("n%1").arg(i));
        x.writeAttribute(QStringLiteral("in"), QString::number(o.in));
        x.writeAttribute(QStringLiteral("out"), QString::number(o.out));
        x.writeEndElement();
        x.writeEndElement();

        // Prostokąt całego obrazu źródła; przy kole widoczny krąg ma średnicę scale × szerokość kadru
        const double D = o.scale * W;
        double w = D, h = D / o.aspect;
        if (circle) {
            w = o.aspect >= 1 ? D * o.aspect : D;
            h = o.aspect >= 1 ? D : D / o.aspect;
        }
        auto rect = [&](double k, double dy, double opacity) {
            const double ww = w * k, hh = h * k;
            return QStringLiteral("%1 %2 %3 %4 %5").arg(qRound(o.x / 100 * W - ww / 2)).arg(qRound(o.y / 100 * H - hh / 2 + dy * H))
                .arg(qRound(ww)).arg(qRound(hh)).arg(num(opacity * o.opacity));
        };
        const int ramp = qBound(2, len / 4, 8), lastF = len - 1;
        QString r;
        if (o.anim == QLatin1String("pojawianie"))
            r = QStringLiteral("0=%1;%2=%3;%4=%3;%5=%6").arg(rect(1, 0, 0)).arg(ramp).arg(rect(1, 0, 1)).arg(lastF - ramp).arg(lastF).arg(rect(1, 0, 0));
        else if (o.anim == QLatin1String("wyskok"))
            r = QStringLiteral("0=%1;%2=%3;%4=%5;%6=%5;%7=%8").arg(rect(0.55, 0, 0)).arg(ramp).arg(rect(1.06, 0, 1)).arg(ramp + 3).arg(rect(1, 0, 1))
                    .arg(lastF - ramp).arg(lastF).arg(rect(0.7, 0, 0));
        else if (o.anim == QLatin1String("wjazd"))
            r = QStringLiteral("0=%1;%2=%3;%4=%3;%5=%6").arg(rect(1, 0.3, 0)).arg(ramp + 2).arg(rect(1, 0, 1)).arg(lastF - ramp).arg(lastF).arg(rect(1, 0, 0));
        else
            r = rect(1, 0, 1);
        overlayRects << r;
        overlayRotations << num(o.rotation);
    }

    x.writeStartElement(QStringLiteral("tractor"));
    x.writeAttribute(QStringLiteral("id"), QStringLiteral("film"));
    x.writeAttribute(QStringLiteral("in"), QStringLiteral("0"));
    x.writeAttribute(QStringLiteral("out"), QString::number(total - 1));
    x.writeStartElement(QStringLiteral("multitrack"));
    auto track = [&](const QString &producer, bool audioOnly) {
        x.writeStartElement(QStringLiteral("track"));
        x.writeAttribute(QStringLiteral("producer"), producer);
        if (audioOnly)
            x.writeAttribute(QStringLiteral("hide"), QStringLiteral("video"));
        x.writeEndElement();
    };
    track(QStringLiteral("tlo"), false);
    track(QStringLiteral("wideo"), false);
    for (int i = 0; i < m_overlays.size(); ++i)
        track(QStringLiteral("nakladka%1").arg(i), false);
    for (int i = 0; i < m_music.size(); ++i)
        track(QStringLiteral("muzyka%1").arg(i), true);
    x.writeEndElement();
    // Dźwięk: wszystko mieszane do ścieżki tła (0)
    const int firstOverlay = 2, firstMusic = 2 + m_overlays.size();
    for (int t = 1; t < firstMusic + m_music.size(); ++t) {
        if (t >= firstOverlay && t < firstMusic && m_overlays.at(t - firstOverlay).kind == QLatin1String("image"))
            continue;
        x.writeStartElement(QStringLiteral("transition"));
        prop(QStringLiteral("mlt_service"), QStringLiteral("mix"));
        prop(QStringLiteral("a_track"), QStringLiteral("0"));
        prop(QStringLiteral("b_track"), QString::number(t));
        prop(QStringLiteral("always_active"), QStringLiteral("1"));
        prop(QStringLiteral("sum"), QStringLiteral("1"));
        x.writeEndElement();
    }
    // Obraz: przy nakładkach główną ścieżkę trzeba wprost nałożyć na tło, a nakładki — na wynik
    if (!m_overlays.isEmpty()) {
        x.writeStartElement(QStringLiteral("transition"));
        prop(QStringLiteral("mlt_service"), QStringLiteral("qtblend"));
        prop(QStringLiteral("a_track"), QStringLiteral("0"));
        prop(QStringLiteral("b_track"), QStringLiteral("1"));
        prop(QStringLiteral("always_active"), QStringLiteral("1"));
        x.writeEndElement();
        for (int i = 0; i < m_overlays.size(); ++i) {
            const Overlay &o = m_overlays.at(i);
            x.writeStartElement(QStringLiteral("transition"));
            x.writeAttribute(QStringLiteral("in"), QString::number(o.start));
            x.writeAttribute(QStringLiteral("out"), QString::number(o.start + o.out - o.in));
            prop(QStringLiteral("mlt_service"), QStringLiteral("affine"));
            prop(QStringLiteral("a_track"), QStringLiteral("0"));
            prop(QStringLiteral("b_track"), QString::number(firstOverlay + i));
            prop(QStringLiteral("rect"), overlayRects.at(i));
            prop(QStringLiteral("fill"), QStringLiteral("1"));
            prop(QStringLiteral("distort"), QStringLiteral("0"));
            prop(QStringLiteral("halign"), QStringLiteral("center"));
            prop(QStringLiteral("valign"), QStringLiteral("middle"));
            if (overlayRotations.at(i) != QLatin1String("0"))
                prop(QStringLiteral("fix_rotate_x"), overlayRotations.at(i));
            x.writeEndElement();
        }
    }
    // Napisy — filtry na całym filmie, każdy w swoim przedziale czasu
    for (const Text &t : m_texts) {
        if (t.text.trimmed().isEmpty())
            continue;
        const Style &s = styleOf(t.style);
        const TextLayout L = layoutText(t, W, H);
        const int size = L.size;
        const QString str = L.text, valign = L.valign;
        auto rect = [&](double dx, double dy) {
            return QStringLiteral("%1 %2 %3 %4").arg(qRound(L.x + dx * W)).arg(qRound(L.y + dy * H)).arg(qRound(L.w)).arg(qRound(L.h));
        };
        // Animacja: wejście i wyjście po ok. 0,3 s (krócej przy krótkim napisie)
        const int ramp = qBound(2, t.length / 4, 9);
        QString geometry = rect(0, 0), opacity;
        if (t.anim != QLatin1String("brak") && t.anim != QLatin1String("pisanie"))
            opacity = QStringLiteral("0=0;%1=1;-%2=1;-1=0").arg(ramp).arg(ramp + 1);
        if (t.anim == QLatin1String("wjazd"))
            geometry = QStringLiteral("0=%1;%2=%3").arg(rect(0, 0.07)).arg(ramp).arg(rect(0, 0));
        else if (t.anim == QLatin1String("bok"))
            geometry = QStringLiteral("0=%1;%2=%3").arg(rect(0.3, 0)).arg(ramp + 3).arg(rect(0, 0));      // wjazd z prawej
        QList<QPair<QString, QString>> props = {
            {QStringLiteral("geometry"), geometry}, {QStringLiteral("family"), QStringLiteral("Geist")},
            {QStringLiteral("size"), QString::number(size)}, {QStringLiteral("weight"), QString::number(s.weight)},
            {QStringLiteral("fgcolour"), t.color.isEmpty() ? QString::fromLatin1(s.fg) : t.color},
            {QStringLiteral("bgcolour"), QString::fromLatin1(s.bg)}, {QStringLiteral("olcolour"), QString::fromLatin1(s.ol)},
            {QStringLiteral("outline"), QString::number(s.outline > 0 ? qMax(1, qRound(size * s.outline)) : 0)},
            {QStringLiteral("pad"), QString::number(QByteArray(s.bg).startsWith("#00") ? 0 : qRound(size * 0.35))},
            {QStringLiteral("halign"), QStringLiteral("center")}, {QStringLiteral("valign"), valign}};
        if (!opacity.isEmpty())
            props << qMakePair(QStringLiteral("opacity"), opacity);
        if (t.anim == QLatin1String("pisanie")) {
            // „Pisanie”: kolejne filtry z coraz dłuższym początkiem tekstu (ok. 2 klatki na znak, najwyżej 1,5 s)
            const int n = str.size();
            const int steps = qMax(1, qMin(n, qMin(24, t.length / 3)));
            const int reveal = qMin(qMin(n * 2, 45), t.length * 2 / 3);
            int at = t.start;
            for (int i = 1; i <= steps; ++i) {
                const int next = i == steps ? t.start + t.length : t.start + reveal * i / steps;
                if (next <= at)
                    continue;
                auto p = props;
                p.prepend(qMakePair(QStringLiteral("argument"), str.left(qMax(1, n * i / steps))));
                filter(QStringLiteral("qtext"), p, at, next - 1);
                at = next;
            }
        } else {
            props.prepend(qMakePair(QStringLiteral("argument"), str));
            filter(QStringLiteral("qtext"), props, t.start, t.start + t.length - 1);
        }
    }
    // Rozjaśnienie z czerni na początku i ściemnienie na końcu (obraz i dźwięk, po 0,5 s)
    const int fadeLen = qMin(15, total / 3);
    if (m_fadeIn && fadeLen > 1) {
        filter(QStringLiteral("brightness"), {{QStringLiteral("level"), QStringLiteral("0=0;%1=1").arg(fadeLen - 1)}}, 0, fadeLen - 1);
        filter(QStringLiteral("volume"), {{QStringLiteral("gain"), QStringLiteral("0")}, {QStringLiteral("end"), QStringLiteral("1")}}, 0, fadeLen - 1);
    }
    if (m_fadeOut && fadeLen > 1) {
        filter(QStringLiteral("brightness"), {{QStringLiteral("level"), QStringLiteral("0=1;%1=0").arg(fadeLen - 1)}}, total - fadeLen, total - 1);
        filter(QStringLiteral("volume"), {{QStringLiteral("gain"), QStringLiteral("1")}, {QStringLiteral("end"), QStringLiteral("0")}}, total - fadeLen, total - 1);
    }
    x.writeEndElement();
    x.writeEndElement();
    x.writeEndDocument();
    return out;
}

Project::TextLayout Project::layoutText(const Text &t, int W, int H) const
{
    const Style &s = styleOf(t.style);
    TextLayout L;
    L.size = qMax(8, qRound(s.size * qMin(W, H) * t.scale));
    const int maxChars = qMax(4, int(0.86 * W / (L.size * 0.56)));
    L.text = wrapText(s.upper ? t.text.toUpper() : t.text, maxChars);
    const QStringList lines = L.text.split(QLatin1Char('\n'));
    L.lines = lines.size();
    for (const QString &l : lines)
        L.longest = qMax(L.longest, int(l.size()));
    const QString place = QString::fromLatin1(s.place);
    L.w = 0.88 * W;
    if (t.x >= 0 && t.y >= 0) {
        // Miejsce wybrane przeciągnięciem na podglądzie: środek napisu w (x, y)
        L.h = L.lines * L.size * 1.4 + L.size;
        L.x = t.x / 100.0 * W - L.w / 2;
        L.y = t.y / 100.0 * H - L.h / 2;
        L.valign = QStringLiteral("middle");
    } else {
        L.x = 0.06 * W;
        L.y = (place == QLatin1String("top") ? 0.08 : place == QLatin1String("middle") ? 0.30 : place == QLatin1String("lower") ? 0.56 : 0.66) * H;
        L.h = (place == QLatin1String("middle") ? 0.40 : place == QLatin1String("bottom") ? 0.24 : 0.22) * H;
        L.valign = place == QLatin1String("top") ? QStringLiteral("top")
                 : place == QLatin1String("bottom") ? QStringLiteral("bottom") : QStringLiteral("middle");
    }
    return L;
}

QVariantMap Project::textBox(const QString &id) const
{
    for (const Text &t : m_texts) {
        if (t.id != id)
            continue;
        const int W = width(), H = height();
        const TextLayout L = layoutText(t, W, H);
        const Style &s = styleOf(t.style);
        const double pad = QByteArray(s.bg).startsWith("#00") ? 0 : L.size * 0.35;
        const double tw = qMin(L.w, L.longest * L.size * 0.56 + 2 * pad + L.size * 0.4), th = L.lines * L.size * 1.25 + 2 * pad;
        const double cy = L.valign == QLatin1String("middle") ? L.y + L.h / 2 : L.valign == QLatin1String("bottom") ? L.y + L.h - th / 2 : L.y + th / 2;
        return {{QStringLiteral("x"), (L.x + L.w / 2) / W}, {QStringLiteral("y"), cy / H}, {QStringLiteral("w"), tw / W}, {QStringLiteral("h"), th / H}};
    }
    return {};
}

bool Project::saveMlt(const QString &pathOrUrl) const
{
    QSaveFile f(toPath(pathOrUrl));
    if (!f.open(QIODevice::WriteOnly))
        return false;
    f.write(xml(width(), height()).toUtf8());
    return f.commit();
}

// ——— Pomocnicze ———

QString Project::time(int frames, bool fine) const
{
    frames = qMax(0, frames);
    const int s = frames / Fps, f = frames % Fps;
    QString t = s >= 3600 ? QStringLiteral("%1:%2:%3").arg(s / 3600).arg(s / 60 % 60, 2, 10, QLatin1Char('0')).arg(s % 60, 2, 10, QLatin1Char('0'))
                          : QStringLiteral("%1:%2").arg(s / 60).arg(s % 60, 2, 10, QLatin1Char('0'));
    if (fine)
        t += QStringLiteral(",%1").arg(f, 2, 10, QLatin1Char('0'));
    return t;
}

QString Project::toPath(const QString &pathOrUrl) const
{
    const QUrl url(pathOrUrl);
    return url.isLocalFile() ? url.toLocalFile() : pathOrUrl;
}

QString Project::videosDir() const
{
    return QStandardPaths::writableLocation(QStandardPaths::MoviesLocation);
}

QString Project::when(qint64 msecs) const
{
    const QDate d = QDateTime::fromMSecsSinceEpoch(msecs).date();
    const QDate today = QDate::currentDate();
    if (d == today)
        return QStringLiteral("dziś");
    if (d == today.addDays(-1))
        return QStringLiteral("wczoraj");
    const QLocale pl(QLocale::Polish);
    return d.year() == today.year() ? pl.toString(d, QStringLiteral("d MMMM")) : pl.toString(d, QStringLiteral("d MMMM yyyy"));
}

void Project::showInFolder(const QString &path) const
{
    QDBusMessage m = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.FileManager1"), QStringLiteral("/org/freedesktop/FileManager1"),
                                                    QStringLiteral("org.freedesktop.FileManager1"), QStringLiteral("ShowItems"));
    m << QStringList{QUrl::fromLocalFile(path).toString()} << QString();
    if (!QDBusConnection::sessionBus().send(m))
        QDesktopServices::openUrl(QUrl::fromLocalFile(QFileInfo(path).absolutePath()));
}

QString Project::thumbUrl(const QString &path, int frame, const QString &look)
{
    if (path.isEmpty())
        return QString();
    return QStringLiteral("image://mthumb/%1/").arg(qMax(0, frame))
           + QString::fromLatin1(path.toUtf8().toBase64(QByteArray::Base64UrlEncoding | QByteArray::OmitTrailingEquals))
           + (look.isEmpty() ? QString() : QLatin1Char('/') + look);
}

QString Project::wave(const QString &path) const
{
    if (path.isEmpty())
        return QString();
    return QStringLiteral("image://mwave/") + QString::fromLatin1(path.toUtf8().toBase64(QByteArray::Base64UrlEncoding | QByteArray::OmitTrailingEquals));
}
