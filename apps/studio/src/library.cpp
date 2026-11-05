// Biblioteka dźwięków (folder Biblioteka obok projektów) i zapisane ustawienia kanałów oraz insertów.
#include "studio.h"

#include <QCoreApplication>

#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPointer>
#include <QStandardPaths>
#include <QThreadPool>
#include <QUrl>

QString Studio::libraryFolder() const
{
    const QString dir = projectsFolder() + QStringLiteral("/Biblioteka");
    QDir().mkpath(dir);
    return dir;
}

QVariantList Studio::library() const
{
    QVariantList out;
    const QStringList filters{QStringLiteral("*.wav"), QStringLiteral("*.flac"), QStringLiteral("*.mp3"), QStringLiteral("*.ogg"), QStringLiteral("*.aiff")};
    const QString root = libraryFolder();
    QDirIterator it(root, filters, QDir::Files, QDirIterator::Subdirectories);
    QStringList paths;
    while (it.hasNext() && paths.size() < 3000)
        paths << it.next();
    paths.sort(Qt::CaseInsensitive);
    for (const QString &p : std::as_const(paths)) {
        const QFileInfo fi(p);
        out.append(QVariantMap{{QStringLiteral("path"), p}, {QStringLiteral("name"), fi.completeBaseName()},
                               {QStringLiteral("folder"), QDir(root).relativeFilePath(fi.absolutePath())}});
    }
    return out;
}

int Studio::addSample(const QString &pathOrUrl)
{
    if (!isOpen())
        return 0;
    const QUrl url(pathOrUrl);
    const QString path = url.isLocalFile() ? url.toLocalFile() : pathOrUrl;
    const QFileInfo fi(path);
    if (!fi.isFile())
        return 0;
    // Do projektu trafia kopia: projekt zostaje kompletny, nawet gdy biblioteka się zmieni
    QString target = m_folder + QStringLiteral("/audio/") + fi.fileName();
    const bool same = QFileInfo::exists(target) && QFileInfo(target).size() == fi.size();
    if (!same) {
        target = uniqueAudioPath(fi.completeBaseName(), fi.suffix().toLower());
        if (!QFile::copy(path, target)) {
            emit message(QStringLiteral("Nie udało się skopiować „%1”.").arg(fi.fileName()));
            return 0;
        }
    }
    return addChannel(QStringLiteral("sampler"), QFileInfo(target).fileName());
}

void Studio::previewFile(const QString &path)
{
    QPointer<Studio> self(this);
    QThreadPool::globalInstance()->start([self, path] {
        std::shared_ptr<AudioSource> src = loadAudio(path, Engine::Rate);
        QMetaObject::invokeMethod(qApp, [self, src] {
            if (self && src)
                self->m_engine.preview(src, 0.8f);
        });
    });
}

// ——— Ustawienia ———

static QString presetsDir(const QString &kind)
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + QStringLiteral("/presety/") + kind;
    QDir().mkpath(dir);
    return dir;
}

QVariantList Studio::presetList(const QString &kind) const
{
    QVariantList out;
    for (const QFileInfo &fi : QDir(presetsDir(kind)).entryInfoList({QStringLiteral("*.json")}, QDir::Files, QDir::Name))
        out.append(QVariantMap{{QStringLiteral("path"), fi.filePath()}, {QStringLiteral("name"), fi.completeBaseName()}});
    return out;
}

bool Studio::savePreset(const QString &kind, int id, const QString &rawName)
{
    QString name = rawName.trimmed();
    name.replace(QLatin1Char('/'), QLatin1Char('-'));
    if (name.isEmpty())
        return false;
    QJsonObject o;
    if (kind == QLatin1String("channel")) {
        const Channel *c = findChannel(id);
        if (!c)
            return false;
        o = QJsonObject{{QStringLiteral("for"), c->kind}, {QStringLiteral("attack"), c->attack}, {QStringLiteral("decay"), c->decay},
                        {QStringLiteral("sustain"), c->sustain}, {QStringLiteral("release"), c->release}, {QStringLiteral("tune"), c->tune},
                        {QStringLiteral("cutoff"), c->cutoff}, {QStringLiteral("resonance"), c->resonance}, {QStringLiteral("loop"), c->loop},
                        {QStringLiteral("oneShot"), c->oneShot}, {QStringLiteral("choke"), c->choke}};
        if (c->vst.plugin) {
            o.insert(QStringLiteral("uid"), c->vst.info.uid);
            o.insert(QStringLiteral("state"), QString::fromLatin1(c->vst.plugin->state().toBase64()));
        }
    } else {
        const Insert *in = findInsert(id);
        if (!in)
            return false;
        o = insertJson(*in, true);
    }
    QFile f(presetsDir(kind) + QLatin1Char('/') + name + QStringLiteral(".json"));
    if (!f.open(QIODevice::WriteOnly))
        return false;
    f.write(QJsonDocument(o).toJson());
    emit presetsChanged();
    emit message(QStringLiteral("Zapisano ustawienie „%1”.").arg(name));
    return true;
}

void Studio::loadPreset(const QString &kind, int id, const QString &path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return;
    const QJsonObject o = QJsonDocument::fromJson(f.readAll()).object();
    checkpoint();
    if (kind == QLatin1String("channel")) {
        Channel *c = findChannel(id);
        if (!c)
            return;
        c->attack = o.value(QStringLiteral("attack")).toDouble(c->attack);
        c->decay = o.value(QStringLiteral("decay")).toDouble(c->decay);
        c->sustain = o.value(QStringLiteral("sustain")).toDouble(c->sustain);
        c->release = o.value(QStringLiteral("release")).toDouble(c->release);
        c->tune = o.value(QStringLiteral("tune")).toDouble(c->tune);
        c->cutoff = o.value(QStringLiteral("cutoff")).toDouble(c->cutoff);
        c->resonance = o.value(QStringLiteral("resonance")).toDouble(c->resonance);
        c->loop = o.value(QStringLiteral("loop")).toBool(c->loop);
        c->oneShot = o.value(QStringLiteral("oneShot")).toBool(c->oneShot);
        c->choke = o.value(QStringLiteral("choke")).toInt(c->choke);
        if (c->vst.plugin) {
            if (o.value(QStringLiteral("uid")).toString() == c->vst.info.uid)
                c->vst.plugin->setState(QByteArray::fromBase64(o.value(QStringLiteral("state")).toString().toLatin1()));
            else
                emit message(QStringLiteral("To ustawienie jest dla innej wtyczki."));
        } else {
            rebuildInstrument(*c);
        }
    } else {
        Insert *in = findInsert(id);
        if (!in)
            return;
        // Brzmienie insertu: efekty i wtyczki; nazwa, wysyłki i poziom zostają
        Insert loaded = insertFromJson(o, {});
        for (Slot &s : loaded.slots_) {
            s.id = m_nextId++;
            s.side = 0;
        }
        const Insert keep = *in;
        *in = loaded;
        in->id = keep.id;
        in->name = keep.name;
        in->color = keep.color;
        in->volume = keep.volume;
        in->pan = keep.pan;
        in->mute = keep.mute;
        in->solo = keep.solo;
        in->sends = keep.sends;
        in->toMaster = keep.toMaster;
        in->duckFrom = keep.duckFrom;
        in->frozen.clear();
    }
    changed(false);
}
