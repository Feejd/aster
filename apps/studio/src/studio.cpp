#include "studio.h"
#include "beatsynth.h"

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
#include <QSet>
#include <QSettings>
#include <QStandardPaths>
#include <QThreadPool>
#include <QUrl>
#include <cmath>
#include <sndfile.h>

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
    // Ścieżki wzorów idą za tempem: te same takty, nowe pętle
    const double ratio = m_bpm / v;
    m_bpm = v;
    for (int i = 0; i < m_tracks.size(); ++i) {
        if (m_tracks[i].kind == QLatin1String("audio"))
            continue;
        for (Clip &c : m_tracks[i].clips) {
            c.start = llround(c.start * ratio);
            c.length = llround(c.length * ratio);
        }
        renderPattern(i);
    }
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

bool Studio::newProject(const QString &rawName, double bpm, int beatsPerBar, const QString &templ)
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
    m_reverbSize = 0.5;
    m_clickVolume = 0.7;
    m_mastering = {};
    m_echoTime = QStringLiteral("3/16");
    m_keyRoot = 9;
    m_keyMinor = true;
    m_cycle = false;
    m_cycleStart = m_cycleEnd = 0;
    m_engine.setCycle(false, 0, 0);
    emit cycleChanged();
    m_engine.setMetronome(true);
    m_tracks.clear();
    m_undo.clear();
    m_redo.clear();
    const QVariantMap genre = [&] {
        for (const QVariant &g : BeatSynth::genres())
            if (g.toMap().value(QStringLiteral("id")).toString() == templ)
                return g.toMap();
        return QVariantMap();
    }();
    if (genre.isEmpty()) {
        addTrack(QStringLiteral("Wokal"));
        addTrack(QStringLiteral("Gitara"));
    } else {
        // Szablon gatunku: bit, 808, wokal z łańcuchem efektów i mastering — od razu brzmi jak gotowy podkład
        m_bpm = genre.value(QStringLiteral("bpm")).toDouble();
        m_beatsPerBar = 4;
        const bool trap = templ == QLatin1String("trap") || templ == QLatin1String("drill");
        addTrack(QStringLiteral("Wokal"));
        applyPresetTo(m_tracks.last(), trap ? QStringLiteral("trapvocal") : templ == QLatin1String("boombap") ? QStringLiteral("rap") : QStringLiteral("vocal"));
        addTrack(QStringLiteral("Wokal 2"));
        applyPresetTo(m_tracks.last(), QStringLiteral("backing"));
        m_tracks.last().pan = -0.2;
        // Podkład trochę ciszej — zostaje miejsce na głos
        m_tracks[addPatternTrack(QStringLiteral("drums"), templ)].volume = -4;
        m_tracks[addPatternTrack(QStringLiteral("bass"), templ)].volume = -5;
        m_tracks[addPatternTrack(QStringLiteral("keys"), templ)].volume = -7;
        applyMasteringPreset(trap ? QStringLiteral("trap") : templ == QLatin1String("boombap") ? QStringLiteral("warm")
                             : templ == QLatin1String("lofi") ? QStringLiteral("lofi") : templ == QLatin1String("house") ? QStringLiteral("loud") : QStringLiteral("pop"));
        m_echoTime = trap ? QStringLiteral("3/16") : QStringLiteral("1/4");
        keyFrom808();
        changed(false);
    }
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
    // Pętle Beat Makera („_…”) z wcześniejszych wersji wzoru — po zamknięciu cofanie i tak znika, więc można je usunąć
    QSet<QString> used;
    for (const Track &t : m_tracks)
        for (const Clip &c : t.clips)
            used.insert(c.file);
    const QDir audio(m_folder + QStringLiteral("/audio"));
    for (const QString &f : audio.entryList({QStringLiteral("_*.wav")}, QDir::Files))
        if (!used.contains(f))
            QFile::remove(audio.filePath(f));
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
                                     {QStringLiteral("fadeIn"), double(c.fadeIn)},
                                     {QStringLiteral("fadeOut"), double(c.fadeOut)},
                                     {QStringLiteral("gain"), c.gain},
                                     {QStringLiteral("loop"), c.loop}});
        tracks.append(QJsonObject{{QStringLiteral("id"), t.id},
                                  {QStringLiteral("name"), t.name},
                                  {QStringLiteral("color"), t.color},
                                  {QStringLiteral("volume"), t.volume},
                                  {QStringLiteral("pan"), t.pan},
                                  {QStringLiteral("mute"), t.mute},
                                  {QStringLiteral("solo"), t.solo},
                                  {QStringLiteral("input"), t.input},
                                  {QStringLiteral("effects"), QJsonObject{{QStringLiteral("preset"), t.preset},
                                                                          {QStringLiteral("lowCut"), t.lowCut},
                                                                          {QStringLiteral("eqLow"), t.eqLow},
                                                                          {QStringLiteral("eqMid"), t.eqMid},
                                                                          {QStringLiteral("eqHigh"), t.eqHigh},
                                                                          {QStringLiteral("compression"), t.comp},
                                                                          {QStringLiteral("reverb"), t.reverb},
                                                                          {QStringLiteral("echo"), t.echo},
                                                                          {QStringLiteral("drive"), t.drive},
                                                                          {QStringLiteral("autotune"), t.tune}}},
                                  {QStringLiteral("kind"), t.kind},
                                  {QStringLiteral("pattern"), t.pattern},
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
                       {QStringLiteral("reverbSize"), m_reverbSize},
                       {QStringLiteral("clickVolume"), m_clickVolume},
                       {QStringLiteral("cycle"), m_cycle},
                       {QStringLiteral("echoTime"), m_echoTime},
                       {QStringLiteral("key"), QJsonObject{{QStringLiteral("root"), m_keyRoot}, {QStringLiteral("minor"), m_keyMinor}}},
                       {QStringLiteral("mastering"), QJsonObject{{QStringLiteral("preset"), m_mastering.preset},
                                                                {QStringLiteral("eqLow"), m_mastering.eqLow},
                                                                {QStringLiteral("eqHigh"), m_mastering.eqHigh},
                                                                {QStringLiteral("compression"), m_mastering.comp},
                                                                {QStringLiteral("width"), m_mastering.width},
                                                                {QStringLiteral("drive"), m_mastering.drive}}},
                       {QStringLiteral("cycleStart"), m_cycleStart},
                       {QStringLiteral("cycleEnd"), m_cycleEnd},
                       {QStringLiteral("tracks"), tracks}};
}

void Studio::fromJson(const QJsonObject &o)
{
    m_bpm = std::clamp(o.value(QStringLiteral("bpm")).toDouble(120), 30.0, 300.0);
    m_beatsPerBar = std::clamp(o.value(QStringLiteral("beatsPerBar")).toInt(4), 1, 12);
    m_metronome = o.value(QStringLiteral("metronome")).toBool(true);
    m_countIn = o.value(QStringLiteral("countIn")).toBool(true);
    m_masterDb = o.value(QStringLiteral("masterVolume")).toDouble(0);
    m_reverbSize = std::clamp(o.value(QStringLiteral("reverbSize")).toDouble(0.5), 0.0, 1.0);
    m_clickVolume = std::clamp(o.value(QStringLiteral("clickVolume")).toDouble(0.7), 0.0, 1.0);
    m_cycleStart = std::max(0.0, o.value(QStringLiteral("cycleStart")).toDouble());
    m_cycleEnd = std::max(m_cycleStart, o.value(QStringLiteral("cycleEnd")).toDouble());
    m_cycle = o.value(QStringLiteral("cycle")).toBool() && m_cycleEnd > m_cycleStart;
    m_echoTime = o.value(QStringLiteral("echoTime")).toString(QStringLiteral("3/16"));
    const QJsonObject ko = o.value(QStringLiteral("key")).toObject();
    m_keyRoot = std::clamp(ko.value(QStringLiteral("root")).toInt(9), 0, 11);
    m_keyMinor = ko.value(QStringLiteral("minor")).toBool(true);
    const QJsonObject mo = o.value(QStringLiteral("mastering")).toObject();
    m_mastering.preset = mo.value(QStringLiteral("preset")).toString();
    m_mastering.eqLow = std::clamp(mo.value(QStringLiteral("eqLow")).toDouble(), -12.0, 12.0);
    m_mastering.eqHigh = std::clamp(mo.value(QStringLiteral("eqHigh")).toDouble(), -12.0, 12.0);
    m_mastering.comp = std::clamp(mo.value(QStringLiteral("compression")).toDouble(), 0.0, 1.0);
    m_mastering.width = std::clamp(mo.value(QStringLiteral("width")).toDouble(1), 0.0, 2.0);
    m_mastering.drive = std::clamp(mo.value(QStringLiteral("drive")).toDouble(), 0.0, 12.0);
    m_engine.setCycle(m_cycle, frames(m_cycleStart), frames(m_cycleEnd));
    emit cycleChanged();
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
        const QJsonObject fx = to.value(QStringLiteral("effects")).toObject();
        t.preset = fx.value(QStringLiteral("preset")).toString();
        t.lowCut = fx.value(QStringLiteral("lowCut")).toBool();
        t.eqLow = std::clamp(fx.value(QStringLiteral("eqLow")).toDouble(), -12.0, 12.0);
        t.eqMid = std::clamp(fx.value(QStringLiteral("eqMid")).toDouble(), -12.0, 12.0);
        t.eqHigh = std::clamp(fx.value(QStringLiteral("eqHigh")).toDouble(), -12.0, 12.0);
        t.comp = std::clamp(fx.value(QStringLiteral("compression")).toDouble(), 0.0, 1.0);
        t.reverb = std::clamp(fx.value(QStringLiteral("reverb")).toDouble(), 0.0, 1.0);
        t.echo = std::clamp(fx.value(QStringLiteral("echo")).toDouble(), 0.0, 1.0);
        t.drive = std::clamp(fx.value(QStringLiteral("drive")).toDouble(), 0.0, 1.0);
        t.tune = std::clamp(fx.value(QStringLiteral("autotune")).toDouble(), 0.0, 1.0);
        t.kind = to.value(QStringLiteral("kind")).toString(QStringLiteral("audio"));
        t.pattern = to.value(QStringLiteral("pattern")).toObject();
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
            c.fadeIn = std::max(0LL, fr(co.value(QStringLiteral("fadeIn"))));
            c.fadeOut = std::max(0LL, fr(co.value(QStringLiteral("fadeOut"))));
            c.gain = std::clamp(co.value(QStringLiteral("gain")).toDouble(), -36.0, 12.0);
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
                                     {QStringLiteral("fadeIn"), c.fadeIn / R},
                                     {QStringLiteral("fadeOut"), c.fadeOut / R},
                                     {QStringLiteral("gain"), c.gain},
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
                                        {QStringLiteral("kind"), t.kind},
                                        {QStringLiteral("pattern"), t.pattern.toVariantMap()},
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
                                     {QStringLiteral("solo"), t.solo},
                                     {QStringLiteral("eqLow"), t.eqLow},
                                     {QStringLiteral("eqMid"), t.eqMid},
                                     {QStringLiteral("eqHigh"), t.eqHigh},
                                     {QStringLiteral("comp"), t.comp},
                                     {QStringLiteral("reverb"), t.reverb},
                                     {QStringLiteral("lowCut"), t.lowCut},
                                     {QStringLiteral("echo"), t.echo},
                                     {QStringLiteral("drive"), t.drive},
                                     {QStringLiteral("tune"), t.tune},
                                     {QStringLiteral("preset"), t.preset}});
    emit mixChanged();
}

Snapshot *Studio::buildSnapshot() const
{
    auto *s = new Snapshot;
    s->bpm = m_bpm;
    s->beatsPerBar = m_beatsPerBar;
    s->master = float(dbToGain(m_masterDb));
    s->reverbSize = float(m_reverbSize);
    s->click = float(m_clickVolume);
    const double echoBeats = m_echoTime == QLatin1String("1/4") ? 1.0 : m_echoTime == QLatin1String("1/8") ? 0.5 : 0.75;
    s->echoDelay = int(echoBeats * 60.0 / m_bpm * Engine::Rate);
    {
        const double R = Engine::Rate;
        MasterParams &mp = s->mastering;
        mp.low = Biquad::lowShelf(90, m_mastering.eqLow, R);
        mp.high = Biquad::highShelf(9000, m_mastering.eqHigh, R);
        if (m_mastering.comp > 0.01) {
            // Łagodny kompresor „sklejający” miks (niski stosunek, wolniejszy niż na ścieżkach)
            mp.comp.on = true;
            mp.comp.threshold = float(-6 - 14 * m_mastering.comp);
            mp.comp.ratio = float(1.5 + 2.5 * m_mastering.comp);
            mp.comp.makeup = float(std::pow(10.0, (-mp.comp.threshold * (1 - 1 / mp.comp.ratio) * 0.4) / 20));
        }
        mp.width = float(m_mastering.width);
        mp.drive = float(dbToGain(m_mastering.drive));
    }
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
        const double R = Engine::Rate;
        if (t.lowCut)
            rt.eq[0] = Biquad::highPass(80, R);
        rt.eq[1] = Biquad::lowShelf(150, t.eqLow, R);
        rt.eq[2] = Biquad::peak(1200, t.eqMid, 0.8, R);
        rt.eq[3] = Biquad::highShelf(6500, t.eqHigh, R);
        rt.comp = CompParams::fromAmount(t.comp);
        rt.send = float(t.reverb * 0.6);
        rt.echo = float(t.echo * 0.7);
        rt.drive = float(t.drive);
        if (t.tune > 0.005) {
            static const int minor[7] = {0, 2, 3, 5, 7, 8, 10}, major[7] = {0, 2, 4, 5, 7, 9, 11};
            uint16_t mask = 0;
            for (int d = 0; d < 7; ++d)
                mask |= uint16_t(1u << ((m_keyRoot + (m_keyMinor ? minor[d] : major[d])) % 12));
            rt.tune.on = true;
            rt.tune.amount = float(t.tune);
            rt.tune.scale = mask;
        }
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
            r.fadeIn = c.fadeIn;
            r.fadeOut = c.fadeOut;
            r.gain = float(dbToGain(c.gain));
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
    if (on && m_tracks[index].kind != QLatin1String("audio"))
        return;                                 // ścieżki Beat Makera nie nagrywają
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
    if (m_tracks[track].kind != m_tracks[from].kind)
        track = from;                           // nagranie nie wskakuje na ścieżkę bitu i odwrotnie
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
    cutStart(*findClip(id), d);
    changed();
}

void Studio::cutStart(Clip &c, long long d)
{
    c.start += d;
    c.length -= d;
    if (c.loop) {
        // Treść zostaje na miejscu — przesuwa się tylko faza pętli
        c.offset = ((c.offset + d) % c.srcLen + c.srcLen) % c.srcLen;
    } else {
        c.srcStart += d;
        c.srcLen -= d;
    }
    c.fadeIn = std::max(0LL, c.fadeIn - d);
    c.fadeOut = std::min(c.fadeOut, c.length);
}

// Wycina fragment [a, b) z klipów ścieżki (poza klipem keepId): nowe nagranie zastępuje to, co było pod spodem
void Studio::carve(int track, long long a, long long b, int keepId)
{
    QList<Clip> out;
    for (Clip c : m_tracks[track].clips) {
        const long long cs = c.start, ce = c.start + c.length;
        if (c.id == keepId || ce <= a || cs >= b) {
            out.append(c);
            continue;
        }
        if (cs < a) {                       // zostaje część przed
            Clip left = c;
            left.length = a - cs;
            if (!left.loop)
                left.srcLen = left.length;
            left.fadeOut = 0;
            out.append(left);
        }
        if (ce > b) {                       // i część po
            Clip right = c;
            if (cs < a)
                right.id = m_nextId++;
            cutStart(right, b - cs);
            right.fadeIn = 0;
            out.append(right);
        }
    }
    m_tracks[track].clips = out;
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
    c->fadeOut = 0;
    right.fadeIn = 0;
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
                if (ti < 0 || ti >= st->m_tracks.size() || i > 0 || st->m_tracks[ti].kind != QLatin1String("audio")) {
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
        // Zaznaczona ścieżka nagrania, a gdy zaznaczony jest bit — pierwsza ścieżka nagrania (albo nowa)
        ti = std::clamp(m_selTrack, 0, int(m_tracks.size()) - 1);
        if (ti < 0 || m_tracks[ti].kind != QLatin1String("audio")) {
            ti = -1;
            for (int i = 0; i < m_tracks.size() && ti < 0; ++i)
                if (m_tracks[i].kind == QLatin1String("audio"))
                    ti = i;
            if (ti < 0) {
                addTrack(QStringLiteral("Wokal"));
                ti = int(m_tracks.size()) - 1;
            }
        }
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
    carve(ti, c.start, c.start + c.length, 0);
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
    // Na wybrzmienie: pół sekundy, a z pogłosem — tyle, ile wybrzmiewa sala
    bool reverb = false;
    for (const Track &t : m_tracks)
        reverb |= t.reverb > 0 && !t.mute;
    const long long total = end + llround(Engine::Rate * (reverb ? 1.5 + 3.0 * m_reverbSize : 0.5));
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

// ——— Efekty ———

namespace {
// Gotowe brzmienia (własne ustawienia, typowe dla gatunków)
struct FxPreset
{
    const char *id, *label, *group, *hint;
    bool lowCut;
    double low, mid, high, comp, reverb, echo, drive, tune;
};
const FxPreset s_presets[] = {
    {"none", "Bez efektów", "", "Czysty dźwięk", false, 0, 0, 0, 0, 0, 0, 0, 0},
    {"vocal", "Wokal pop", "Wokal", "Wyraźny i równy, z lekką salą, delikatny autotune", true, -2, 1.5, 3, 0.5, 0.25, 0.1, 0, 0.35},
    {"trapvocal", "Wokal trap", "Wokal", "Mocny autotune, jasny, ściśnięty, echo ósemki z kropką", true, -3, 1, 5, 0.75, 0.18, 0.3, 0.15, 0.9},
    {"rap", "Rap", "Wokal", "Blisko i sucho — każde słowo słychać", true, -2, 2, 3, 0.65, 0.06, 0, 0.1, 0},
    {"backing", "Chórki / dubel", "Wokal", "Szerzej i dalej, pod głównym wokalem", true, -4, -1, 4, 0.5, 0.45, 0.15, 0, 0.6},
    {"guitar", "Gitara", "Instrumenty", "Klarowna, z odrobiną sali", true, -1, 0, 2, 0.3, 0.2, 0.05, 0, 0},
    {"bass", "Bas", "Instrumenty", "Pełny dół, równy poziom", false, 3, -2, -1, 0.6, 0, 0, 0.2, 0},
    {"drums", "Perkusja", "Instrumenty", "Mocne uderzenie, trochę sali", false, 2, -2, 2, 0.4, 0.1, 0, 0.1, 0},
    {"keys", "Klawisze", "Instrumenty", "Akordy w tle: jasno, z salą i echem", true, -2, 0, 1.5, 0.25, 0.3, 0.12, 0, 0},
    {"808", "808", "Instrumenty", "Przester dla słyszalności na telefonie", false, 2, 0, 0, 0.3, 0, 0, 0.35, 0},
    {"radio", "Radio", "Efekty", "Wąsko, jak z małego głośniczka", true, -12, 8, -10, 0.7, 0, 0, 0.4, 0},
    {"lofi", "Lo-fi", "Efekty", "Ciemno i ciepło, jak ze starej taśmy", false, 1, -1, -8, 0.3, 0.15, 0, 0.3, 0},
    {"hall", "Daleko", "Efekty", "Dużo pogłosu, jak w kościele", true, 0, 0, 1, 0.15, 0.55, 0.1, 0, 0},
};

struct MasterPreset
{
    const char *id, *label, *hint;
    double low, high, comp, width, drive;
};
const MasterPreset s_masterPresets[] = {
    {"none", "Bez masteringu", "Miks tak, jak jest", 0, 0, 0, 1, 0},
    {"trap", "Trap / hip-hop", "Mocny dół, jasna góra, głośno", 3, 2, 0.4, 1.15, 3},
    {"pop", "Pop", "Wyraźnie i szeroko", 1, 2.5, 0.4, 1.12, 5},
    {"warm", "Ciepły", "Miękko, bez ostrości", 2, -1.5, 0.35, 1.0, 4},
    {"loud", "Głośny", "Jak najgłośniej, do klubu", 1.5, 1.5, 0.5, 1.1, 5.5},
    {"lofi", "Lo-fi", "Ciemno i blisko", 1, -4, 0.3, 0.9, 3},
};
}

QVariantList Studio::presets() const
{
    QVariantList list;
    for (const FxPreset &p : s_presets)
        list.append(QVariantMap{{QStringLiteral("id"), QString::fromUtf8(p.id)}, {QStringLiteral("label"), QString::fromUtf8(p.label)},
                                {QStringLiteral("group"), QString::fromUtf8(p.group)}, {QStringLiteral("hint"), QString::fromUtf8(p.hint)}});
    return list;
}

void Studio::applyPresetTo(Track &t, const QString &preset)
{
    for (const FxPreset &p : s_presets) {
        if (preset != QLatin1String(p.id))
            continue;
        t.lowCut = p.lowCut;
        t.eqLow = p.low;
        t.eqMid = p.mid;
        t.eqHigh = p.high;
        t.comp = p.comp;
        t.reverb = p.reverb;
        t.echo = p.echo;
        t.drive = p.drive;
        t.tune = p.tune;
        t.preset = preset == QLatin1String("none") ? QString() : preset;
    }
}

void Studio::applyPreset(int index, const QString &preset)
{
    if (index < 0 || index >= m_tracks.size())
        return;
    checkpoint();
    applyPresetTo(m_tracks[index], preset);
    changed(false);
}

QVariantMap Studio::mastering() const
{
    return {{QStringLiteral("preset"), m_mastering.preset}, {QStringLiteral("eqLow"), m_mastering.eqLow},
            {QStringLiteral("eqHigh"), m_mastering.eqHigh}, {QStringLiteral("comp"), m_mastering.comp},
            {QStringLiteral("width"), m_mastering.width}, {QStringLiteral("drive"), m_mastering.drive}};
}

QVariantList Studio::masteringPresets() const
{
    QVariantList list;
    for (const MasterPreset &p : s_masterPresets)
        list.append(QVariantMap{{QStringLiteral("id"), QString::fromUtf8(p.id)}, {QStringLiteral("label"), QString::fromUtf8(p.label)},
                                {QStringLiteral("hint"), QString::fromUtf8(p.hint)}});
    return list;
}

void Studio::applyMasteringPreset(const QString &preset)
{
    for (const MasterPreset &p : s_masterPresets)
        if (preset == QLatin1String(p.id))
            m_mastering = {p.low, p.high, p.comp, p.width, p.drive, preset == QLatin1String("none") ? QString() : preset};
}

void Studio::applyMastering(const QString &preset)
{
    checkpoint();
    applyMasteringPreset(preset);
    emit settingsChanged();
    changed(false);
}

void Studio::setMastering(const QString &key, double value)
{
    if (key == QLatin1String("eqLow"))
        m_mastering.eqLow = std::clamp(value, -12.0, 12.0);
    else if (key == QLatin1String("eqHigh"))
        m_mastering.eqHigh = std::clamp(value, -12.0, 12.0);
    else if (key == QLatin1String("comp"))
        m_mastering.comp = std::clamp(value, 0.0, 1.0);
    else if (key == QLatin1String("width"))
        m_mastering.width = std::clamp(value, 0.0, 2.0);
    else if (key == QLatin1String("drive"))
        m_mastering.drive = std::clamp(value, 0.0, 12.0);
    else
        return;
    m_mastering.preset.clear();
    emit settingsChanged();
    changed(false);
}

void Studio::setEchoTime(const QString &t)
{
    if (t == m_echoTime || (t != QLatin1String("1/4") && t != QLatin1String("1/8") && t != QLatin1String("3/16")))
        return;
    m_echoTime = t;
    emit settingsChanged();
    changed(false);
}

void Studio::setTrackFx(int index, const QString &key, double value)
{
    if (index < 0 || index >= m_tracks.size())
        return;
    Track &t = m_tracks[index];
    if (key == QLatin1String("eqLow"))
        t.eqLow = std::clamp(value, -12.0, 12.0);
    else if (key == QLatin1String("eqMid"))
        t.eqMid = std::clamp(value, -12.0, 12.0);
    else if (key == QLatin1String("eqHigh"))
        t.eqHigh = std::clamp(value, -12.0, 12.0);
    else if (key == QLatin1String("comp"))
        t.comp = std::clamp(value, 0.0, 1.0);
    else if (key == QLatin1String("reverb"))
        t.reverb = std::clamp(value, 0.0, 1.0);
    else if (key == QLatin1String("lowCut"))
        t.lowCut = value != 0;
    else if (key == QLatin1String("echo"))
        t.echo = std::clamp(value, 0.0, 1.0);
    else if (key == QLatin1String("drive"))
        t.drive = std::clamp(value, 0.0, 1.0);
    else if (key == QLatin1String("tune"))
        t.tune = std::clamp(value, 0.0, 1.0);
    else
        return;
    t.preset.clear();               // ręczna zmiana — już nie gotowe ustawienie
    changed(false);
}

void Studio::setReverbSize(double v)
{
    v = std::clamp(v, 0.0, 1.0);
    if (v == m_reverbSize)
        return;
    m_reverbSize = v;
    emit settingsChanged();
    changed(false);
}

void Studio::setClickVolume(double v)
{
    v = std::clamp(v, 0.0, 1.0);
    if (v == m_clickVolume)
        return;
    m_clickVolume = v;
    emit settingsChanged();
    changed(false);
}

// ——— Klipy: głośność, narastanie i wyciszanie, nazwa ———
// Suwaki wołają remember() przy chwyceniu, więc całe przeciągnięcie cofa się jednym Ctrl+Z

void Studio::setClipGain(int id, double db)
{
    Clip *c = findClip(id);
    if (!c)
        return;
    c->gain = std::clamp(db, -36.0, 12.0);
    changed();
}

void Studio::setClipFades(int id, double fadeIn, double fadeOut)
{
    Clip *c = findClip(id);
    if (!c)
        return;
    c->fadeIn = std::clamp(frames(fadeIn), 0LL, c->length);
    c->fadeOut = std::clamp(frames(fadeOut), 0LL, c->length - c->fadeIn);
    changed();
}

void Studio::renameClip(int id, const QString &name)
{
    Clip *c = findClip(id);
    if (!c || name.trimmed().isEmpty() || name.trimmed() == c->name)
        return;
    checkpoint();
    findClip(id)->name = name.trimmed();
    changed();
}

// ——— Region pętli odtwarzania ———

void Studio::setCycle(double start, double end)
{
    start = std::max(0.0, start);
    if (end - start < 0.05)
        return;
    m_cycleStart = start;
    m_cycleEnd = end;
    m_cycle = true;
    m_engine.setCycle(true, frames(start), frames(end));
    emit cycleChanged();
    setDirty(true);
}

void Studio::setCycleOn(bool on)
{
    if (on && m_cycleEnd - m_cycleStart < 0.05) {
        // Pierwsze włączenie: cztery takty od taktu z głowicą
        const double bar = 60.0 / m_bpm * m_beatsPerBar;
        const double start = std::floor(std::max(0.0, m_position) / bar) * bar;
        setCycle(start, start + 4 * bar);
        return;
    }
    if (on == m_cycle)
        return;
    m_cycle = on;
    m_engine.setCycle(on, frames(m_cycleStart), frames(m_cycleEnd));
    emit cycleChanged();
    setDirty(true);
}

void Studio::cycleClip(int id)
{
    if (Clip *c = findClip(id))
        setCycle(double(c->start) / Engine::Rate, double(c->start + c->length) / Engine::Rate);
}

// ——— Beat Maker ———

QVariantList Studio::kits() const { return BeatSynth::kits(); }
QVariantList Studio::genres() const { return BeatSynth::genres(); }
QVariantList Studio::instruments() const { return BeatSynth::instruments(); }
QVariantList Studio::rhythms() const { return BeatSynth::rhythms(); }
QVariantList Studio::progressions() const { return BeatSynth::progressions(); }

QString Studio::chordName(int degree, bool seventh) const
{
    return BeatSynth::chordName(m_keyRoot, m_keyMinor, degree, seventh);
}

static BeatSynth::Kind kindOf(const QString &kind)
{
    return kind == QLatin1String("bass") ? BeatSynth::Bass : kind == QLatin1String("keys") ? BeatSynth::Keys : BeatSynth::Drums;
}

void Studio::renderKeyTracks()
{
    for (int i = 0; i < m_tracks.size(); ++i)
        if (m_tracks[i].kind == QLatin1String("keys"))
            renderPattern(i);
}

QVariantMap Studio::genrePattern(const QString &kind, const QString &genre) const
{
    return BeatSynth::genrePattern(genre, kindOf(kind)).toVariantMap();
}

QString Studio::noteName(int root, int degree) const
{
    static const char *names[12] = {"C", "Cis", "D", "Dis", "E", "F", "Fis", "G", "Gis", "A", "B", "H"};
    const int midi = BeatSynth::noteMidi(QJsonObject{{QStringLiteral("root"), root}}, std::clamp(degree, 0, 14));
    return QString::fromUtf8(names[midi % 12]) + QString::number(midi / 12 - 1);
}

int Studio::addPatternTrack(const QString &kind, const QString &genre)
{
    if (!isOpen() || m_tracks.size() >= Renderer::MaxTracks)
        return -1;
    const BeatSynth::Kind k = kindOf(kind);
    addTrack(k == BeatSynth::Bass ? QStringLiteral("808") : k == BeatSynth::Keys ? QStringLiteral("Akordy") : QStringLiteral("Bit"));   // zapamiętuje stan do cofnięcia
    Track &t = m_tracks.last();
    t.kind = k == BeatSynth::Bass ? QStringLiteral("bass") : k == BeatSynth::Keys ? QStringLiteral("keys") : QStringLiteral("drums");
    t.pattern = BeatSynth::genrePattern(genre.isEmpty() ? QStringLiteral("trap") : genre, k);
    applyPresetTo(t, k == BeatSynth::Bass ? QStringLiteral("808") : k == BeatSynth::Keys ? QStringLiteral("keys") : QStringLiteral("drums"));
    if (k == BeatSynth::Keys && genre == QLatin1String("trap"))
        t.echo = 0.25;                          // dzwonki w trapie z echem
    renderPattern(int(m_tracks.size()) - 1);
    changed();
    return int(m_tracks.size()) - 1;
}

void Studio::setPattern(int index, const QVariantMap &pattern)
{
    if (index < 0 || index >= m_tracks.size() || m_tracks[index].kind == QLatin1String("audio"))
        return;
    checkpoint();
    m_tracks[index].pattern = QJsonObject::fromVariantMap(pattern);
    renderPattern(index);
    changed();
}

// Wzór → pętla audio zapisana w audio/ (nazwa z „_”, nowa przy każdej zmianie — cofanie wraca do poprzedniego pliku)
void Studio::renderPattern(int index)
{
    Track &t = m_tracks[index];
    const BeatSynth::Kind kind = kindOf(t.kind);
    QJsonObject pattern = t.pattern;
    pattern.insert(QStringLiteral("keyRoot"), m_keyRoot);
    pattern.insert(QStringLiteral("keyMinor"), m_keyMinor);
    std::shared_ptr<AudioSource> src = BeatSynth::render(pattern, kind, m_bpm, Engine::Rate);
    const QString path = uniqueAudioPath(kind == BeatSynth::Bass ? QStringLiteral("_808") : kind == BeatSynth::Keys ? QStringLiteral("_akordy")
                                                                                                                   : QStringLiteral("_bit"),
                                         QStringLiteral("wav"));
    SF_INFO info{};
    info.samplerate = Engine::Rate;
    info.channels = src->channels;
    info.format = SF_FORMAT_WAV | SF_FORMAT_PCM_24;
    if (SNDFILE *sf = sf_open(QFile::encodeName(path).constData(), SFM_WRITE, &info)) {
        sf_writef_float(sf, src->data.data(), src->frames);
        sf_close(sf);
    }
    src->file = QFileInfo(path).fileName();
    m_sources.insert(src->file, src);
    ++m_sourcesVersion;
    emit sourcesChanged();
    if (t.clips.isEmpty()) {
        // Pierwszy klip: osiem taktów albo do końca piosenki
        const long long bar = llround(60.0 / m_bpm * m_beatsPerBar * Engine::Rate);
        const long long songEnd = frames(duration());
        Clip c;
        c.id = m_nextId++;
        c.name = t.name;
        c.length = std::max(8 * bar, (songEnd + bar - 1) / bar * bar);
        t.clips.append(c);
    }
    for (Clip &c : t.clips) {
        c.file = src->file;
        c.srcStart = 0;
        c.srcLen = src->frames;
        c.offset = ((c.offset % src->frames) + src->frames) % src->frames;
        c.loop = true;
    }
}

// ——— Tonacja (autotune) ———

void Studio::setKeyRoot(int r)
{
    r = ((r % 12) + 12) % 12;
    if (r == m_keyRoot)
        return;
    m_keyRoot = r;
    renderKeyTracks();
    emit settingsChanged();
    changed();
}

void Studio::setKeyMinor(bool m)
{
    if (m == m_keyMinor)
        return;
    m_keyMinor = m;
    renderKeyTracks();
    emit settingsChanged();
    changed();
}

QString Studio::keyName() const
{
    static const char *names[12] = {"C", "Cis", "D", "Dis", "E", "F", "Fis", "G", "Gis", "A", "B", "H"};
    const QString n = QString::fromUtf8(names[m_keyRoot]);
    return m_keyMinor ? n.toLower() + QStringLiteral("-moll") : n + QStringLiteral("-dur");
}

bool Studio::keyFrom808()
{
    for (const Track &t : m_tracks)
        if (t.kind == QLatin1String("bass")) {
            m_keyRoot = std::clamp(t.pattern.value(QStringLiteral("root")).toInt(), 0, 11);
            m_keyMinor = true;                  // 808 gra w skali molowej
            renderKeyTracks();
            emit settingsChanged();
            changed();
            return true;
        }
    return false;
}
