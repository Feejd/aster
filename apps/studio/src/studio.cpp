#include "studio.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QPointer>
#include <QSettings>
#include <QStandardPaths>
#include <QThreadPool>
#include <QUrl>
#include <cmath>

static const QString ProjectFile = QStringLiteral("projekt.json");
static constexpr int Colors = 8;               // paleta kolorów ścieżek (w Main.qml)

static double dbToGain(double db) { return db <= -59.9 ? 0.0 : std::pow(10.0, db / 20.0); }

static QString localPath(const QString &pathOrUrl)
{
    const QUrl url(pathOrUrl);
    return url.isLocalFile() ? url.toLocalFile() : pathOrUrl;
}

Studio::Studio(QObject *parent) : QObject(parent)
{
    s_instance = this;
    QSettings st;
    m_engine.setOutput(st.value(QStringLiteral("audio/output")).toString());
    m_engine.setInput(st.value(QStringLiteral("audio/input")).toString());
    m_latencyMs = st.value(QStringLiteral("audio/latency"), 0.0).toDouble();
    m_engine.setLatencyOffset(llround(m_latencyMs * Engine::Rate / 1000.0));
    if (!m_engine.start())
        m_audioError = m_engine.error();
    connect(&m_engine, &Engine::devicesChanged, this, &Studio::devicesChanged);
    connect(&m_engine, &Engine::streamError, this, [this](const QString &msg) {
        m_audioError = msg.isEmpty() ? QStringLiteral("Urządzenie dźwięku przestało działać.") : msg;
        emit audioErrorChanged();
    });
    m_timer.setInterval(33);
    connect(&m_timer, &QTimer::timeout, this, &Studio::tick);
    m_timer.start();
}

Studio::~Studio()
{
    if (recording())
        finishRecording();
    s_instance = nullptr;
}

// ——— Ustawienia projektu ———

void Studio::setBpm(double v)
{
    v = std::clamp(std::round(v * 10) / 10, 30.0, 300.0);
    if (v == m_bpm)
        return;
    checkpoint();
    m_bpm = v;
    emit settingsChanged();
    changed();
}

void Studio::setBeatsPerBar(int v)
{
    v = std::clamp(v, 1, 12);
    if (v == m_beatsPerBar)
        return;
    checkpoint();
    m_beatsPerBar = v;
    emit settingsChanged();
    changed();
}

void Studio::setMetronome(bool v)
{
    if (v == m_metronome)
        return;
    m_metronome = v;
    m_engine.setMetronome(v);
    emit settingsChanged();
    setDirty(true);
}

void Studio::setCountIn(bool v)
{
    if (v == m_countIn)
        return;
    m_countIn = v;
    emit settingsChanged();
    setDirty(true);
}

void Studio::setMasterVolume(double db)
{
    db = std::clamp(db, -60.0, 6.0);
    if (db == m_masterDb)
        return;
    m_masterDb = db;
    emit settingsChanged();
    changed(false);
}

void Studio::setSelectedTrack(int i)
{
    if (i == m_selTrack)
        return;
    m_selTrack = i;
    emit selectionChanged();
}

void Studio::setSelectedClip(int id)
{
    if (id == m_selClip)
        return;
    m_selClip = id;
    emit selectionChanged();
}

double Studio::duration() const
{
    long long end = 0;
    for (const Track &t : m_tracks)
        for (const Clip &c : t.clips)
            end = std::max(end, c.start + c.length);
    return double(end) / Engine::Rate;
}

void Studio::setOutput(const QString &name)
{
    m_engine.setOutput(name);
    QSettings().setValue(QStringLiteral("audio/output"), name);
    emit devicesChanged();
}

void Studio::setInput(const QString &name)
{
    m_engine.setInput(name);
    QSettings().setValue(QStringLiteral("audio/input"), name);
    emit devicesChanged();
}

void Studio::setLatency(double ms)
{
    m_latencyMs = std::clamp(ms, -500.0, 500.0);
    m_engine.setLatencyOffset(llround(m_latencyMs * Engine::Rate / 1000.0));
    QSettings().setValue(QStringLiteral("audio/latency"), m_latencyMs);
    emit devicesChanged();
}

QVariantList Studio::devices(bool input) const
{
    QVariantList list{QVariantMap{{QStringLiteral("name"), QString()}, {QStringLiteral("label"), QStringLiteral("Domyślne w systemie")}}};
    for (const AudioDevice &d : m_engine.devices())
        if (d.input == input)
            list.append(QVariantMap{{QStringLiteral("name"), d.name}, {QStringLiteral("label"), d.label}});
    return list;
}

// ——— Projekt ———

QString Studio::projectsFolder() const
{
    QString music = QStandardPaths::writableLocation(QStandardPaths::MusicLocation);
    if (music.isEmpty())
        music = QDir::homePath();
    return music + QStringLiteral("/Studio");
}

QString Studio::suggestName() const
{
    for (int i = 1;; ++i) {
        const QString n = i == 1 ? QStringLiteral("Moja piosenka") : QStringLiteral("Moja piosenka %1").arg(i);
        if (!QFileInfo::exists(projectsFolder() + QLatin1Char('/') + n))
            return n;
    }
}

bool Studio::newProject(const QString &rawName, double bpm, int beatsPerBar)
{
    QString name = rawName.trimmed();
    name.replace(QLatin1Char('/'), QLatin1Char('-'));
    if (name.isEmpty() || name.startsWith(QLatin1Char('.')))
        name = suggestName();
    QString folder = projectsFolder() + QLatin1Char('/') + name;
    for (int i = 2; QFileInfo::exists(folder); ++i)
        folder = projectsFolder() + QLatin1Char('/') + name + QLatin1Char(' ') + QString::number(i);
    if (!QDir().mkpath(folder + QStringLiteral("/audio"))) {
        emit message(QStringLiteral("Nie udało się utworzyć folderu projektu."));
        return false;
    }
    closeProject();
    m_folder = folder;
    m_name = QFileInfo(folder).fileName();
    m_bpm = std::clamp(bpm, 30.0, 300.0);
    m_beatsPerBar = std::clamp(beatsPerBar, 1, 12);
    m_metronome = true;
    m_countIn = true;
    m_masterDb = 0;
    m_engine.setMetronome(true);
    m_tracks.clear();
    m_undo.clear();
    m_redo.clear();
    addTrack(QStringLiteral("Wokal"));
    addTrack(QStringLiteral("Gitara"));
    m_undo.clear();
    m_selTrack = 0;
    m_selClip = 0;
    save();
    emit projectChanged();
    emit settingsChanged();
    emit historyChanged();
    emit selectionChanged();
    seek(0);
    return true;
}

bool Studio::openProject(const QString &pathOrUrl)
{
    QString path = localPath(pathOrUrl);
    if (QFileInfo(path).isDir())
        path += QLatin1Char('/') + ProjectFile;
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        emit message(QStringLiteral("Nie udało się otworzyć projektu."));
        return false;
    }
    const QJsonObject o = QJsonDocument::fromJson(f.readAll()).object();
    if (o.value(QStringLiteral("format")).toString() != QLatin1String("aster-studio")) {
        emit message(QStringLiteral("To nie jest projekt Studia."));
        return false;
    }
    closeProject();
    m_folder = QFileInfo(path).absolutePath();
    m_name = QFileInfo(m_folder).fileName();
    fromJson(o);
    m_undo.clear();
    m_redo.clear();
    m_selTrack = 0;
    m_selClip = 0;
    QStringList files;
    for (const Track &t : m_tracks)
        for (const Clip &c : t.clips)
            if (!files.contains(c.file))
                files << c.file;
    loadSources(files);
    addRecent(m_folder);
    setDirty(false);
    emit projectChanged();
    emit settingsChanged();
    emit historyChanged();
    emit selectionChanged();
    seek(0);
    return true;
}

bool Studio::save()
{
    if (!isOpen())
        return false;
    QDir().mkpath(m_folder);
    QFile f(m_folder + QLatin1Char('/') + ProjectFile);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        emit message(QStringLiteral("Nie udało się zapisać projektu."));
        return false;
    }
    f.write(QJsonDocument(toJson()).toJson());
    f.close();
    addRecent(m_folder);
    setDirty(false);
    return true;
}

void Studio::closeProject()
{
    if (!isOpen())
        return;
    stop();
    if (m_dirty)
        save();
    m_folder.clear();
    m_name.clear();
    m_tracks.clear();
    m_sources.clear();
    m_undo.clear();
    m_redo.clear();
    changed();
    setDirty(false);
    emit projectChanged();
    emit historyChanged();
}

void Studio::setDirty(bool d)
{
    if (d == m_dirty)
        return;
    m_dirty = d;
    emit dirtyChanged();
}

QJsonObject Studio::toJson() const
{
    QJsonArray tracks;
    for (const Track &t : m_tracks) {
        QJsonArray clips;
        for (const Clip &c : t.clips)
            clips.append(QJsonObject{{QStringLiteral("id"), c.id},
                                     {QStringLiteral("file"), c.file},
                                     {QStringLiteral("name"), c.name},
                                     {QStringLiteral("start"), double(c.start)},
                                     {QStringLiteral("length"), double(c.length)},
                                     {QStringLiteral("srcStart"), double(c.srcStart)},
                                     {QStringLiteral("srcLength"), double(c.srcLen)},
                                     {QStringLiteral("loopOffset"), double(c.offset)},
                                     {QStringLiteral("loop"), c.loop}});
        tracks.append(QJsonObject{{QStringLiteral("id"), t.id},
                                  {QStringLiteral("name"), t.name},
                                  {QStringLiteral("color"), t.color},
                                  {QStringLiteral("volume"), t.volume},
                                  {QStringLiteral("pan"), t.pan},
                                  {QStringLiteral("mute"), t.mute},
                                  {QStringLiteral("solo"), t.solo},
                                  {QStringLiteral("input"), t.input},
                                  {QStringLiteral("clips"), clips}});
    }
    return QJsonObject{{QStringLiteral("format"), QStringLiteral("aster-studio")},
                       {QStringLiteral("version"), 1},
                       {QStringLiteral("sampleRate"), Engine::Rate},
                       {QStringLiteral("bpm"), m_bpm},
                       {QStringLiteral("beatsPerBar"), m_beatsPerBar},
                       {QStringLiteral("metronome"), m_metronome},
                       {QStringLiteral("countIn"), m_countIn},
                       {QStringLiteral("masterVolume"), m_masterDb},
                       {QStringLiteral("tracks"), tracks}};
}

void Studio::fromJson(const QJsonObject &o)
{
    m_bpm = std::clamp(o.value(QStringLiteral("bpm")).toDouble(120), 30.0, 300.0);
    m_beatsPerBar = std::clamp(o.value(QStringLiteral("beatsPerBar")).toInt(4), 1, 12);
    m_metronome = o.value(QStringLiteral("metronome")).toBool(true);
    m_countIn = o.value(QStringLiteral("countIn")).toBool(true);
    m_masterDb = o.value(QStringLiteral("masterVolume")).toDouble(0);
    m_engine.setMetronome(m_metronome);
    // Plik z inną częstotliwością (przyszłe wersje) — przeliczamy pozycje
    const double scale = double(Engine::Rate) / o.value(QStringLiteral("sampleRate")).toInt(Engine::Rate);
    auto fr = [scale](const QJsonValue &v) { return llround(v.toDouble() * scale); };
    QList<int> armed;
    for (const Track &t : m_tracks)
        if (t.armed)
            armed << t.id;
    m_tracks.clear();
    for (const QJsonValue &tv : o.value(QStringLiteral("tracks")).toArray()) {
        const QJsonObject to = tv.toObject();
        Track t;
        t.id = to.value(QStringLiteral("id")).toInt();
        if (t.id <= 0)
            t.id = m_nextId++;
        m_nextId = std::max(m_nextId, t.id + 1);
        t.name = to.value(QStringLiteral("name")).toString();
        t.color = to.value(QStringLiteral("color")).toInt() % Colors;
        t.volume = to.value(QStringLiteral("volume")).toDouble();
        t.pan = to.value(QStringLiteral("pan")).toDouble();
        t.mute = to.value(QStringLiteral("mute")).toBool();
        t.solo = to.value(QStringLiteral("solo")).toBool();
        t.input = to.value(QStringLiteral("input")).toInt();
        t.armed = armed.contains(t.id);
        for (const QJsonValue &cv : to.value(QStringLiteral("clips")).toArray()) {
            const QJsonObject co = cv.toObject();
            Clip c;
            c.id = co.value(QStringLiteral("id")).toInt();
            if (c.id <= 0)
                c.id = m_nextId++;
            m_nextId = std::max(m_nextId, c.id + 1);
            c.file = QFileInfo(co.value(QStringLiteral("file")).toString()).fileName();   // tylko w audio/ projektu
            c.name = co.value(QStringLiteral("name")).toString();
            c.start = fr(co.value(QStringLiteral("start")));
            c.length = fr(co.value(QStringLiteral("length")));
            c.srcStart = fr(co.value(QStringLiteral("srcStart")));
            c.srcLen = fr(co.value(QStringLiteral("srcLength")));
            c.offset = fr(co.value(QStringLiteral("loopOffset")));
            c.loop = co.value(QStringLiteral("loop")).toBool();
            if (c.file.isEmpty() || c.length <= 0 || c.srcLen <= 0)
                continue;
            t.clips.append(c);
        }
        m_tracks.append(t);
    }
    emit settingsChanged();
    changed();
}

void Studio::checkpoint()
{
    if (!isOpen())
        return;
    m_undo.append(toJson());
    if (m_undo.size() > 100)
        m_undo.removeFirst();
    m_redo.clear();
    emit historyChanged();
}

void Studio::undo()
{
    if (m_undo.isEmpty() || recording())
        return;
    m_redo.append(toJson());
    fromJson(m_undo.takeLast());
    emit historyChanged();
}

void Studio::redo()
{
    if (m_redo.isEmpty() || recording())
        return;
    m_undo.append(toJson());
    fromJson(m_redo.takeLast());
    emit historyChanged();
}

void Studio::changed(bool structure)
{
    if (structure)
        rebuildView();
    else
        rebuildMix();
    m_engine.setSnapshot(buildSnapshot());
    if (isOpen())
        setDirty(true);
}

void Studio::rebuildView()
{
    m_tracksView.clear();
    const double R = Engine::Rate;
    for (const Track &t : m_tracks) {
        QVariantList clips;
        for (const Clip &c : t.clips) {
            const SourcePtr src = m_sources.value(c.file);
            clips.append(QVariantMap{{QStringLiteral("id"), c.id},
                                     {QStringLiteral("file"), c.file},
                                     {QStringLiteral("name"), c.name},
                                     {QStringLiteral("start"), c.start / R},
                                     {QStringLiteral("length"), c.length / R},
                                     {QStringLiteral("srcStart"), c.srcStart / R},
                                     {QStringLiteral("srcLength"), c.srcLen / R},
                                     {QStringLiteral("loopOffset"), c.offset / R},
                                     {QStringLiteral("srcDuration"), src ? src->frames / R : 0.0},
                                     {QStringLiteral("loop"), c.loop},
                                     {QStringLiteral("missing"), !src && m_loading == 0}});
        }
        m_tracksView.append(QVariantMap{{QStringLiteral("id"), t.id},
                                        {QStringLiteral("name"), t.name},
                                        {QStringLiteral("color"), t.color},
                                        {QStringLiteral("volume"), t.volume},
                                        {QStringLiteral("pan"), t.pan},
                                        {QStringLiteral("mute"), t.mute},
                                        {QStringLiteral("solo"), t.solo},
                                        {QStringLiteral("armed"), t.armed},
                                        {QStringLiteral("input"), t.input},
                                        {QStringLiteral("clips"), clips}});
    }
    rebuildMix();
    while (m_levels.size() < m_tracks.size())
        m_levels.append(0.0);
    while (m_levels.size() > m_tracks.size())
        m_levels.removeLast();
    emit tracksChanged();
}

void Studio::rebuildMix()
{
    m_mixView.clear();
    for (const Track &t : m_tracks)
        m_mixView.append(QVariantMap{{QStringLiteral("volume"), t.volume},
                                     {QStringLiteral("pan"), t.pan},
                                     {QStringLiteral("mute"), t.mute},
                                     {QStringLiteral("solo"), t.solo}});
    emit mixChanged();
}

Snapshot *Studio::buildSnapshot() const
{
    auto *s = new Snapshot;
    s->bpm = m_bpm;
    s->beatsPerBar = m_beatsPerBar;
    s->master = float(dbToGain(m_masterDb));
    bool anySolo = false;
    for (const Track &t : m_tracks)
        anySolo |= t.solo;
    for (const Track &t : m_tracks) {
        TrackRT rt;
        const float g = float(dbToGain(t.volume));
        const float p = float(std::clamp(t.pan, -1.0, 1.0));
        rt.gainL = g * (p > 0 ? 1.f - p : 1.f);
        rt.gainR = g * (p < 0 ? 1.f + p : 1.f);
        rt.audible = anySolo ? t.solo : !t.mute;
        for (const Clip &c : t.clips) {
            const SourcePtr src = m_sources.value(c.file);
            if (!src)
                continue;
            if (std::find(s->keep.begin(), s->keep.end(), src) == s->keep.end())
                s->keep.push_back(src);
            ClipRT r;
            r.src = src.get();
            r.start = c.start;
            r.length = c.length;
            r.srcStart = c.srcStart;
            r.srcLen = c.srcLen;
            r.offset = c.offset;
            r.loop = c.loop;
            rt.clips.push_back(r);
        }
        s->tracks.push_back(std::move(rt));
    }
    return s;
}

// Wczytuje pliki z audio/ w tle; po wczytaniu klipy dostają kształt fali i grają
void Studio::loadSources(const QStringList &files)
{
    if (files.isEmpty())
        return;
    ++m_loading;
    emit busyChanged();
    const QString dir = m_folder + QStringLiteral("/audio/");
    QPointer<Studio> self(this);
    QThreadPool::globalInstance()->start([self, files, dir] {
        QHash<QString, SourcePtr> loaded;
        QStringList errors;
        for (const QString &f : files) {
            QString err;
            if (auto src = loadAudio(dir + f, Engine::Rate, &err)) {
                src->file = f;
                loaded.insert(f, src);
            } else {
                errors << err;
            }
        }
        QMetaObject::invokeMethod(qApp, [self, loaded, errors, dir] {
            if (!self)
                return;
            --self->m_loading;
            emit self->busyChanged();
            if (self->m_folder + QStringLiteral("/audio/") != dir)
                return;              // w międzyczasie otwarto inny projekt
            for (auto it = loaded.begin(); it != loaded.end(); ++it)
                self->m_sources.insert(it.key(), it.value());
            ++self->m_sourcesVersion;
            emit self->sourcesChanged();
            const bool wasDirty = self->m_dirty;
            self->changed();
            self->setDirty(wasDirty);
            if (!errors.isEmpty())
                emit self->message(errors.first());
        });
    });
}

QString Studio::uniqueAudioPath(const QString &base, const QString &ext) const
{
    QString clean = base;
    clean.replace(QLatin1Char('/'), QLatin1Char('-'));
    if (clean.isEmpty())
        clean = QStringLiteral("Dźwięk");
    const QString dir = m_folder + QStringLiteral("/audio/");
    QString path = dir + clean + QLatin1Char('.') + ext;
    for (int i = 2; QFileInfo::exists(path); ++i)
        path = dir + clean + QLatin1Char(' ') + QString::number(i) + QLatin1Char('.') + ext;
    return path;
}

QVariantList Studio::recent() const
{
    QVariantList list;
    const QStringList folders = QSettings().value(QStringLiteral("recent")).toStringList();
    for (const QString &folder : folders) {
        const QFileInfo fi(folder + QLatin1Char('/') + ProjectFile);
        if (!fi.exists())
            continue;
        QFile f(fi.filePath());
        int tracks = 0;
        double bpm = 0;
        if (f.open(QIODevice::ReadOnly)) {
            const QJsonObject o = QJsonDocument::fromJson(f.readAll()).object();
            tracks = int(o.value(QStringLiteral("tracks")).toArray().size());
            bpm = o.value(QStringLiteral("bpm")).toDouble();
        }
        list.append(QVariantMap{{QStringLiteral("folder"), folder},
                                {QStringLiteral("name"), QFileInfo(folder).fileName()},
                                {QStringLiteral("modified"), fi.lastModified()},
                                {QStringLiteral("tracks"), tracks},
                                {QStringLiteral("bpm"), bpm}});
    }
    return list;
}

void Studio::addRecent(const QString &folder)
{
    QSettings st;
    QStringList list = st.value(QStringLiteral("recent")).toStringList();
    list.removeAll(folder);
    list.prepend(folder);
    while (list.size() > 12)
        list.removeLast();
    st.setValue(QStringLiteral("recent"), list);
    emit recentChanged();
}

void Studio::forgetRecent(const QString &folder)
{
    QSettings st;
    QStringList list = st.value(QStringLiteral("recent")).toStringList();
    list.removeAll(folder);
    st.setValue(QStringLiteral("recent"), list);
    emit recentChanged();
}

// ——— Ścieżki ———

void Studio::addTrack(const QString &name)
{
    if (m_tracks.size() >= Renderer::MaxTracks) {
        emit message(QStringLiteral("Projekt może mieć najwyżej %1 ścieżki.").arg(Renderer::MaxTracks));
        return;
    }
    checkpoint();
    Track t;
    t.id = m_nextId++;
    t.name = name.isEmpty() ? QStringLiteral("Ścieżka %1").arg(m_tracks.size() + 1) : name;
    // Kolor: pierwszy nieużywany z palety
    QList<int> used;
    for (const Track &o : m_tracks)
        used << o.color;
    t.color = int(m_tracks.size()) % Colors;
    for (int c = 0; c < Colors; ++c)
        if (!used.contains(c)) {
            t.color = c;
            break;
        }
    m_tracks.append(t);
    m_selTrack = int(m_tracks.size()) - 1;
    emit selectionChanged();
    changed();
}

void Studio::removeTrack(int index)
{
    if (index < 0 || index >= m_tracks.size() || (recording() && index == m_recTrack))
        return;
    checkpoint();
    m_tracks.removeAt(index);
    m_selTrack = std::clamp(m_selTrack, 0, std::max(0, int(m_tracks.size()) - 1));
    emit selectionChanged();
    updateCapture();
    changed();
}

void Studio::renameTrack(int index, const QString &name)
{
    if (index < 0 || index >= m_tracks.size() || name.trimmed().isEmpty() || name.trimmed() == m_tracks[index].name)
        return;
    checkpoint();
    m_tracks[index].name = name.trimmed();
    changed();
}

void Studio::moveTrack(int from, int to)
{
    if (from < 0 || from >= m_tracks.size() || to < 0 || to >= m_tracks.size() || from == to || recording())
        return;
    checkpoint();
    m_tracks.move(from, to);
    m_selTrack = to;
    emit selectionChanged();
    changed();
}

// Głośność i panorama bez cofania (suwaki zmieniają je płynnie); zapisują się z projektem
void Studio::setTrackVolume(int index, double db)
{
    if (index < 0 || index >= m_tracks.size())
        return;
    m_tracks[index].volume = std::clamp(db, -60.0, 6.0);
    changed(false);
}

void Studio::setTrackPan(int index, double pan)
{
    if (index < 0 || index >= m_tracks.size())
        return;
    m_tracks[index].pan = std::clamp(pan, -1.0, 1.0);
    changed(false);
}

void Studio::setTrackMute(int index, bool on)
{
    if (index < 0 || index >= m_tracks.size())
        return;
    m_tracks[index].mute = on;
    changed(false);
}

void Studio::setTrackSolo(int index, bool on)
{
    if (index < 0 || index >= m_tracks.size())
        return;
    m_tracks[index].solo = on;
    changed(false);
}

// Do nagrania gotowa jest jedna ścieżka naraz (prościej dla początkujących)
void Studio::setTrackArmed(int index, bool on)
{
    if (index < 0 || index >= m_tracks.size() || recording())
        return;
    for (int i = 0; i < m_tracks.size(); ++i)
        m_tracks[i].armed = on && i == index;
    if (on) {
        m_selTrack = index;
        emit selectionChanged();
    }
    updateCapture();
    rebuildView();
}

void Studio::setTrackInput(int index, int channel)
{
    if (index < 0 || index >= m_tracks.size())
        return;
    m_tracks[index].input = std::clamp(channel, 0, 2);
    changed();
}

void Studio::updateCapture()
{
    bool any = recording();
    for (const Track &t : m_tracks)
        any |= t.armed;
    m_engine.setCapture(any);
}

// ——— Klipy ———

Studio::Clip *Studio::findClip(int id, int *track)
{
    for (int i = 0; i < m_tracks.size(); ++i)
        for (Clip &c : m_tracks[i].clips)
            if (c.id == id) {
                if (track)
                    *track = i;
                return &c;
            }
    return nullptr;
}

long long Studio::maxSrcLen(const Clip &c) const
{
    const SourcePtr src = m_sources.value(c.file);
    return src ? src->frames - c.srcStart : c.srcLen;
}

QVariantMap Studio::clip(int id) const
{
    for (const QVariant &t : m_tracksView)
        for (const QVariant &c : t.toMap().value(QStringLiteral("clips")).toList())
            if (c.toMap().value(QStringLiteral("id")).toInt() == id)
                return c.toMap();
    return {};
}

void Studio::moveClip(int id, int track, double start)
{
    int from = -1;
    Clip *c = findClip(id, &from);
    if (!c || track < 0 || track >= m_tracks.size())
        return;
    const long long s = std::max(0LL, frames(start));
    if (s == c->start && track == from)
        return;
    checkpoint();
    c = findClip(id, &from);
    c->start = s;
    if (track != from) {
        m_tracks[track].clips.append(*c);
        m_tracks[from].clips.removeIf([id](const Clip &x) { return x.id == id; });
    }
    m_selTrack = track;
    emit selectionChanged();
    changed();
}

void Studio::trimClipStart(int id, double start)
{
    Clip *c = findClip(id);
    if (!c)
        return;
    const long long minLen = Engine::Rate / 20;
    long long d = frames(start) - c->start;
    d = std::min(d, c->length - minLen);
    if (c->loop) {
        d = std::max(d, -c->start);
    } else {
        d = std::max({d, -c->srcStart, -c->start});
        d = std::min(d, c->srcLen - minLen);
    }
    if (d == 0)
        return;
    checkpoint();
    c = findClip(id);
    c->start += d;
    c->length -= d;
    if (c->loop) {
        // Treść zostaje na miejscu — przesuwa się tylko faza pętli
        c->offset = ((c->offset + d) % c->srcLen + c->srcLen) % c->srcLen;
    } else {
        c->srcStart += d;
        c->srcLen -= d;
    }
    changed();
}

void Studio::trimClipEnd(int id, double end)
{
    Clip *c = findClip(id);
    if (!c)
        return;
    const long long minLen = Engine::Rate / 20;
    long long len = std::max(minLen, frames(end) - c->start);
    if (!c->loop)
        len = std::min(len, maxSrcLen(*c));
    if (len == c->length)
        return;
    checkpoint();
    c = findClip(id);
    c->length = len;
    if (!c->loop)
        c->srcLen = len;
    changed();
}

bool Studio::splitClip(int id, double at)
{
    int ti = -1;
    Clip *c = findClip(id, &ti);
    if (!c)
        return false;
    const long long minLen = Engine::Rate / 20;
    const long long t = frames(at) - c->start;
    if (t < minLen || t > c->length - minLen)
        return false;
    checkpoint();
    c = findClip(id, &ti);
    Clip right = *c;
    right.id = m_nextId++;
    right.start = c->start + t;
    right.length = c->length - t;
    if (c->loop) {
        right.offset = (c->offset + t) % c->srcLen;
    } else {
        right.srcStart = c->srcStart + t;
        right.srcLen = c->srcLen - t;
        c->srcLen = t;
    }
    c->length = t;
    m_tracks[ti].clips.append(right);
    m_selClip = right.id;
    emit selectionChanged();
    changed();
    return true;
}

void Studio::setClipLoop(int id, bool on)
{
    Clip *c = findClip(id);
    if (!c || c->loop == on)
        return;
    checkpoint();
    c = findClip(id);
    c->loop = on;
    if (!on) {
        // Bez pętli: klip pokazuje jedno przejście od bieżącej fazy
        c->srcStart += c->offset;
        c->srcLen -= c->offset;
        c->offset = 0;
        c->length = std::min(c->length, c->srcLen);
    }
    changed();
}

void Studio::duplicateClip(int id)
{
    int ti = -1;
    Clip *c = findClip(id, &ti);
    if (!c)
        return;
    checkpoint();
    c = findClip(id, &ti);
    Clip copy = *c;
    copy.id = m_nextId++;
    copy.start = c->start + c->length;
    m_tracks[ti].clips.append(copy);
    m_selClip = copy.id;
    emit selectionChanged();
    changed();
}

void Studio::removeClip(int id)
{
    int ti = -1;
    if (!findClip(id, &ti))
        return;
    checkpoint();
    m_tracks[ti].clips.removeIf([id](const Clip &x) { return x.id == id; });
    if (m_selClip == id) {
        m_selClip = 0;
        emit selectionChanged();
    }
    changed();
}

// Import: pliki kopiują się do audio/ projektu (projekt nie zależy od tego, co stanie się z oryginałem).
// Pierwszy plik trafia na wskazaną ścieżkę, kolejne — na nowe ścieżki, od tego samego miejsca.
void Studio::importFiles(const QVariantList &urls, int track, double start)
{
    if (!isOpen())
        return;
    QStringList paths;
    for (const QVariant &u : urls) {
        const QString p = localPath(u.toUrl().isValid() && !u.toUrl().scheme().isEmpty() ? u.toUrl().toString() : u.toString());
        if (QFileInfo(p).isFile())
            paths << p;
    }
    if (paths.isEmpty())
        return;
    ++m_loading;
    emit busyChanged();
    const QString dir = m_folder + QStringLiteral("/audio/");
    QStringList targets;           // nazwy w audio/ (unikalne także między sobą)
    for (const QString &p : paths) {
        const QFileInfo fi(p);
        QString target = fi.absolutePath() + QLatin1Char('/') == dir ? p : uniqueAudioPath(fi.completeBaseName(), fi.suffix().toLower());
        for (int i = 2; targets.contains(target); ++i)
            target = uniqueAudioPath(fi.completeBaseName() + QLatin1Char(' ') + QString::number(i), fi.suffix().toLower());
        targets << target;
    }
    QPointer<Studio> self(this);
    QThreadPool::globalInstance()->start([self, paths, targets, dir, track, start] {
        QList<std::shared_ptr<AudioSource>> loaded;
        QStringList names, errors;
        for (int i = 0; i < paths.size(); ++i) {
            QString err;
            auto src = loadAudio(paths[i], Engine::Rate, &err);
            if (!src) {
                errors << err;
                continue;
            }
            if (targets[i] != paths[i] && !QFile::copy(paths[i], targets[i])) {
                errors << QStringLiteral("Nie udało się skopiować „%1” do projektu.").arg(QFileInfo(paths[i]).fileName());
                continue;
            }
            src->file = QFileInfo(targets[i]).fileName();
            loaded << src;
            names << QFileInfo(paths[i]).completeBaseName();
        }
        QMetaObject::invokeMethod(qApp, [self, loaded, names, errors, dir, track, start] {
            if (!self)
                return;
            Studio *st = self;
            --st->m_loading;
            emit st->busyChanged();
            if (!errors.isEmpty())
                emit st->message(errors.first());
            if (loaded.isEmpty() || st->m_folder + QStringLiteral("/audio/") != dir)
                return;
            st->checkpoint();
            int ti = track;
            for (int i = 0; i < loaded.size(); ++i) {
                st->m_sources.insert(loaded[i]->file, loaded[i]);
                if (ti < 0 || ti >= st->m_tracks.size() || i > 0) {
                    if (st->m_tracks.size() >= Renderer::MaxTracks)
                        break;
                    Track t;
                    t.id = st->m_nextId++;
                    t.name = names[i];
                    t.color = int(st->m_tracks.size()) % Colors;
                    st->m_tracks.append(t);
                    ti = int(st->m_tracks.size()) - 1;
                }
                Clip c;
                c.id = st->m_nextId++;
                c.file = loaded[i]->file;
                c.name = names[i];
                c.start = std::max(0LL, llround(start * Engine::Rate));
                c.length = c.srcLen = loaded[i]->frames;
                st->m_tracks[ti].clips.append(c);
                if (i == 0) {
                    st->m_selTrack = ti;
                    st->m_selClip = c.id;
                }
            }
            ++st->m_sourcesVersion;
            emit st->sourcesChanged();
            emit st->selectionChanged();
            st->changed();
        });
    });
}

// ——— Transport ———

void Studio::play()
{
    if (!isOpen() || playing())
        return;
    if (!audioOk()) {
        emit message(m_audioError);
        return;
    }
    m_engine.play(frames(m_position));
    emit transportChanged();
}

void Studio::stop()
{
    if (recording()) {
        finishRecording();
        return;
    }
    if (!playing())
        return;
    m_engine.stop();
    emit transportChanged();
}

void Studio::toggle()
{
    if (playing())
        stop();
    else
        play();
}

void Studio::seek(double seconds)
{
    if (recording())
        return;
    m_position = std::max(0.0, seconds);
    m_engine.seek(frames(m_position));
    emit positionChanged();
}

void Studio::record()
{
    if (recording()) {
        finishRecording();
        return;
    }
    if (!isOpen())
        return;
    if (!audioOk()) {
        emit message(m_audioError);
        return;
    }
    // Ścieżka: ta gotowa do nagrania, a gdy żadna nie jest — zaznaczona (albo nowa)
    int ti = -1;
    for (int i = 0; i < m_tracks.size(); ++i)
        if (m_tracks[i].armed)
            ti = i;
    if (ti < 0) {
        if (m_tracks.isEmpty())
            addTrack();
        ti = std::clamp(m_selTrack, 0, int(m_tracks.size()) - 1);
        setTrackArmed(ti, true);
    }
    m_engine.setCapture(true);
    if (playing())
        m_engine.stop();
    m_recTrack = ti;
    m_recPath = uniqueAudioPath(m_tracks[ti].name, QStringLiteral("wav"));
    const long long start = frames(m_position);
    if (!m_engine.startRecording(m_recPath, start, m_tracks[ti].input)) {
        emit message(QStringLiteral("Nie ma wejścia dźwięku — podłącz mikrofon i wybierz go w ustawieniach dźwięku."));
        return;
    }
    const long long preroll = m_countIn ? llround(m_beatsPerBar * 60.0 / m_bpm * Engine::Rate) : 0;
    m_engine.play(start - preroll, m_countIn ? start : Engine::NoSeek);
    m_position = double(start - preroll) / Engine::Rate;
    emit transportChanged();
    emit positionChanged();
}

void Studio::finishRecording()
{
    m_engine.stop();
    long long start = 0;
    const std::shared_ptr<AudioSource> src = m_engine.stopRecording(&start);
    const int ti = m_recTrack;
    m_recTrack = -1;
    emit transportChanged();
    if (!src || src->frames < Engine::Rate / 20 || ti < 0 || ti >= m_tracks.size()) {
        QFile::remove(m_recPath);
        if (!src)
            emit message(QStringLiteral("Nic się nie nagrało — sprawdź mikrofon w ustawieniach dźwięku."));
        return;
    }
    src->file = QFileInfo(m_recPath).fileName();
    m_sources.insert(src->file, src);
    ++m_sourcesVersion;
    emit sourcesChanged();
    checkpoint();
    Clip c;
    c.id = m_nextId++;
    c.file = src->file;
    c.name = QFileInfo(m_recPath).completeBaseName();
    c.start = std::max(0LL, start);
    c.length = c.srcLen = src->frames;
    m_tracks[ti].clips.append(c);
    m_selClip = c.id;
    emit selectionChanged();
    changed();
    save();          // nagrania nie giną, nawet gdy program się zamknie
}

void Studio::tick()
{
    m_engine.collect();
    if (playing()) {
        const double pos = double(m_engine.position()) / Engine::Rate;
        if (pos != m_position) {
            m_position = pos;
            emit positionChanged();
        }
    }
    // Wskaźniki: szczyt z opadaniem
    std::vector<float> peaks(size_t(m_tracks.size()), 0.f);
    float master[2], in[2];
    m_engine.readMeters(peaks, master);
    m_engine.readInputLevel(in);
    bool moving = false;
    auto fall = [&moving](double old, double v) {
        const double r = std::max(v, old * 0.82);
        const double out = r < 0.001 ? 0.0 : r;
        moving |= out != old;
        return out;
    };
    for (int i = 0; i < m_levels.size() && i < int(peaks.size()); ++i)
        m_levels[i] = fall(m_levels[i].toDouble(), peaks[size_t(i)]);
    m_master[0] = fall(m_master[0], master[0]);
    m_master[1] = fall(m_master[1], master[1]);
    m_input = fall(m_input, std::max(in[0], in[1]));
    if (moving)
        emit levelsChanged();
    if (m_exporting) {
        const double p = m_exportShared.load();
        if (p != m_exportProgress) {
            m_exportProgress = p;
            emit exportChanged();
        }
    }
}

// ——— Eksport ———

void Studio::exportMix(const QString &format)
{
    if (!isOpen() || m_exporting)
        return;
    const long long end = frames(duration());
    if (end <= 0) {
        emit exportFinished(false, QString(), QStringLiteral("Projekt jest pusty — nagraj albo dodaj dźwięk."));
        return;
    }
    const QString ext = format == QLatin1String("mp3") || format == QLatin1String("ogg") || format == QLatin1String("flac") ? format : QStringLiteral("wav");
    QDir().mkpath(m_folder + QStringLiteral("/Eksport"));
    const QString path = m_folder + QStringLiteral("/Eksport/") + m_name + QLatin1Char('.') + ext;
    std::shared_ptr<Snapshot> snap(buildSnapshot());
    m_exporting = true;
    m_exportProgress = 0;
    m_exportShared.store(0);
    m_cancelExport.store(false);
    emit exportChanged();
    const long long total = end + Engine::Rate / 2;      // pół sekundy na wybrzmienie
    QPointer<Studio> self(this);
    QThreadPool::globalInstance()->start([self, snap, total, path, ext, this] {
        QString err;
        const bool ok = Engine::exportMix(*snap, total, path, ext, [this](double p) {
            m_exportShared.store(p);
            return !m_cancelExport.load();
        }, &err);
        QMetaObject::invokeMethod(qApp, [self, ok, path, err] {
            if (!self)
                return;
            self->m_exporting = false;
            emit self->exportChanged();
            emit self->exportFinished(ok, path, ok || err.isEmpty() ? err : QStringLiteral("Nie udało się zapisać miksu: ") + err);
        });
    });
}

// ——— Pomocnicze ———

double Studio::snap(double seconds, int division) const
{
    const double beat = 60.0 / m_bpm;
    const double unit = division <= 0 ? beat * m_beatsPerBar : beat / division;
    return std::max(0.0, std::round(seconds / unit) * unit);
}

QString Studio::barBeat(double seconds) const
{
    const double beats = seconds * m_bpm / 60.0;
    const long long b = (long long)std::floor(beats + 1e-6);
    const long long bar = (long long)std::floor(double(b) / m_beatsPerBar);
    const long long beat = b - bar * m_beatsPerBar;
    return QStringLiteral("%1.%2").arg(bar + 1).arg(beat + 1);
}

QString Studio::clock(double seconds) const
{
    const bool neg = seconds < 0;
    const long long tenths = llround(std::fabs(seconds) * 10);
    return QStringLiteral("%1%2:%3,%4").arg(neg ? QStringLiteral("−") : QString()).arg(tenths / 600)
        .arg((tenths / 10) % 60, 2, 10, QLatin1Char('0')).arg(tenths % 10);
}

void Studio::showInFolder(const QString &path) const
{
    QDBusMessage m = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.FileManager1"), QStringLiteral("/org/freedesktop/FileManager1"),
                                                    QStringLiteral("org.freedesktop.FileManager1"), QStringLiteral("ShowItems"));
    m << QStringList{QUrl::fromLocalFile(path).toString()} << QString();
    if (!QDBusConnection::sessionBus().send(m))
        QDesktopServices::openUrl(QUrl::fromLocalFile(QFileInfo(path).absolutePath()));
}

QString Studio::tracksLabel(int n) const
{
    const int t = n % 100, u = n % 10;
    const QString word = n == 1 ? QStringLiteral("ścieżka")
        : (u >= 2 && u <= 4 && (t < 12 || t > 14)) ? QStringLiteral("ścieżki") : QStringLiteral("ścieżek");
    return QString::number(n) + QLatin1Char(' ') + word;
}

QString Studio::when(const QDateTime &t) const
{
    const QDate d = t.date(), today = QDate::currentDate();
    const QString time = t.toString(QStringLiteral("HH:mm"));
    if (d == today)
        return QStringLiteral("Dziś, ") + time;
    if (d == today.addDays(-1))
        return QStringLiteral("Wczoraj, ") + time;
    static const char *months[] = {"stycznia", "lutego", "marca", "kwietnia", "maja", "czerwca", "lipca",
                                   "sierpnia", "września", "października", "listopada", "grudnia"};
    QString s = QString::number(d.day()) + QLatin1Char(' ') + QString::fromUtf8(months[d.month() - 1]);
    if (d.year() != today.year())
        s += QLatin1Char(' ') + QString::number(d.year());
    return s;
}
