#include "studio.h"
#include "analysis.h"
#include "lyrics.h"
#include "denoise.h"
#include "beatsynth.h"
#include "share.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDateTime>
#include <QDesktopServices>
#include <QClipboard>
#include <QDir>
#include <QGuiApplication>
#include <QMimeData>
#include <QProcess>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QLocale>
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
    m_monitor = st.value(QStringLiteral("audio/monitor"), false).toBool();
    if (!m_engine.start())
        m_audioError = m_engine.error();
    connect(&m_engine, &Engine::devicesChanged, this, &Studio::devicesChanged);
    connect(&m_engine, &Engine::streamError, this, [this](const QString &msg) {
        m_audioError = msg.isEmpty() ? QStringLiteral("Urządzenie dźwięku przestało działać.") : msg;
        emit audioErrorChanged();
    });
    connect(&m_midi, &MidiInput::devicesChanged, this, &Studio::midiDevicesChanged);
    connect(&m_midi, &MidiInput::noteOn, this, [this](int p, int v) { emit midiNote(p, v, true); });
    connect(&m_midi, &MidiInput::noteOff, this, [this](int p) { emit midiNote(p, 0, false); });
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
    // Klipy wzorów na playliście też: te same takty
    for (Track &t : m_tracks)
        for (Clip &c : t.clips)
            if (c.pattern || !c.autoTarget.isEmpty()) {
                c.start = llround(c.start * ratio);
                c.length = llround(c.length * ratio);
                c.offset = llround(c.offset * ratio);
                c.srcLen = llround(c.srcLen * ratio);
                for (QPointF &p : c.autoPts)
                    p.setX(p.x() * ratio);
            }
    applyPatternLoop();
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
    rebuildLyrics();
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
    if (i >= 0 && i < m_tracks.size())
        m_selInsert = m_tracks[i].insert;
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

void Studio::setMonitor(bool on)
{
    if (on == m_monitor)
        return;
    m_monitor = on;
    QSettings().setValue(QStringLiteral("audio/monitor"), on);
    updateMonitor();
    emit devicesChanged();
}

void Studio::updateMonitor()
{
    int ti = recording() ? m_recTrack : -1;
    for (int i = 0; i < m_tracks.size() && ti < 0; ++i)
        if (m_tracks[i].armed && m_tracks[i].kind == QLatin1String("audio"))
            ti = i;
    const bool ok = ti >= 0 && ti < m_tracks.size();
    m_engine.setMonitor(m_monitor && ok ? insertIndex(m_tracks[ti].insert) : -1, ok ? m_tracks[ti].input : 0);
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
    clearRack();
    resetLyrics();
    m_undo.clear();
    m_redo.clear();
    const QVariantMap genre = [&] {
        for (const QVariant &g : BeatSynth::genres())
            if (g.toMap().value(QStringLiteral("id")).toString() == templ)
                return g.toMap();
        return QVariantMap();
    }();
    if (templ == QLatin1String("beat")) {
        // Na swoim bicie: zwrotka, dubel i ad-libsy z gotowym brzmieniem; bit dokłada importBeat
        addTrack(QStringLiteral("Wokal"));
        applyPresetTo(ins(m_tracks.last()), QStringLiteral("rap"));
        m_tracks.last().role = QStringLiteral("main");
        addTrack(QStringLiteral("Dubel"));
        applyPresetTo(ins(m_tracks.last()), QStringLiteral("backing"));
        ins(m_tracks.last()).pan = -0.25;
        m_tracks.last().role = QStringLiteral("double");
        addTrack(QStringLiteral("Ad-libsy"));
        applyPresetTo(ins(m_tracks.last()), QStringLiteral("radio"));
        ins(m_tracks.last()).pan = 0.3;
        ins(m_tracks.last()).volume = -3;
        m_tracks.last().role = QStringLiteral("adlib");
        m_metronome = false;                      // rytm słychać w bicie
        m_engine.setMetronome(false);
        changed(false);
    } else if (genre.isEmpty()) {
        addTrack(QStringLiteral("Wokal"));
        addTrack(QStringLiteral("Ścieżka 2"));
        addTrack(QStringLiteral("Ścieżka 3"));
        defaultRack();
    } else {
        // Szablon gatunku: bit, 808, wokal z łańcuchem efektów i mastering — od razu brzmi jak gotowy podkład
        m_bpm = genre.value(QStringLiteral("bpm")).toDouble();
        m_beatsPerBar = 4;
        const bool trap = templ == QLatin1String("trap") || templ == QLatin1String("drill");
        addTrack(QStringLiteral("Wokal"));
        applyPresetTo(ins(m_tracks.last()), trap ? QStringLiteral("trapvocal") : templ == QLatin1String("boombap") ? QStringLiteral("rap") : QStringLiteral("vocal"));
        m_tracks.last().role = QStringLiteral("main");
        addTrack(QStringLiteral("Wokal 2"));
        applyPresetTo(ins(m_tracks.last()), QStringLiteral("backing"));
        ins(m_tracks.last()).pan = -0.2;
        m_tracks.last().role = QStringLiteral("double");
        // Podkład trochę ciszej — zostaje miejsce na głos
        ins(addPatternTrack(QStringLiteral("drums"), templ)).volume = -4;
        ins(addPatternTrack(QStringLiteral("bass"), templ)).volume = -5;
        ins(addPatternTrack(QStringLiteral("keys"), templ)).volume = -7;
        applyMasteringPreset(trap ? QStringLiteral("trap") : templ == QLatin1String("boombap") ? QStringLiteral("warm")
                             : templ == QLatin1String("lofi") ? QStringLiteral("lofi") : templ == QLatin1String("house") ? QStringLiteral("loud") : QStringLiteral("pop"));
        m_echoTime = trap ? QStringLiteral("3/16") : QStringLiteral("1/4");
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
    if (path.endsWith(QLatin1String(".zip"), Qt::CaseInsensitive)) {
        // Paczka od znajomego: rozpakowanie do Muzyka/Studio jako nowy projekt (remiks)
        QDir().mkpath(projectsFolder());
        QString err;
        const QString folder = Share::unpackProject(path, projectsFolder(), &err);
        if (folder.isEmpty()) {
            emit message(err);
            return false;
        }
        if (!openProject(folder))
            return false;
        emit message(QStringLiteral("Otworzono projekt z paczki — możesz go zmieniać i remiksować"));
        return true;
    }
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
    for (const Insert &in : std::as_const(m_inserts))
        used.insert(in.frozen);
    const QDir audio(m_folder + QStringLiteral("/audio"));
    for (const QString &f : audio.entryList({QStringLiteral("_*.wav")}, QDir::Files))
        if (!used.contains(f))
            QFile::remove(audio.filePath(f));
    m_folder.clear();
    m_name.clear();
    m_tracks.clear();
    clearRack();
    resetLyrics();
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

QJsonObject Studio::toJson(bool pluginStates) const
{
    QVariantList marks;
    for (double m : m_lyricMarks)
        marks << m;
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
                                     {QStringLiteral("loop"), c.loop},
                                     {QStringLiteral("takes"), [&] {
                                          QJsonArray a;
                                          for (long long v : c.takes)
                                              a.append(double(v));
                                          return a;
                                      }()},
                                     {QStringLiteral("take"), c.take},
                                     {QStringLiteral("pattern"), c.pattern},
                                     {QStringLiteral("autoTarget"), c.autoTarget},
                                     {QStringLiteral("autoPoints"), [&] {
                                          QJsonArray a;
                                          for (const QPointF &p : c.autoPts)
                                              a.append(QJsonArray{p.x(), p.y()});
                                          return a;
                                      }()},
                                     {QStringLiteral("origFile"), c.origFile}});
        tracks.append(QJsonObject{{QStringLiteral("id"), t.id},
                                  {QStringLiteral("name"), t.name},
                                  {QStringLiteral("color"), t.color},
                                  {QStringLiteral("insert"), t.insert},
                                  {QStringLiteral("input"), t.input},
                                  {QStringLiteral("beat"), t.beat},
                                  {QStringLiteral("role"), t.role},
                                  {QStringLiteral("kind"), t.kind},
                                  {QStringLiteral("pattern"), t.pattern},
                                  {QStringLiteral("clips"), clips}});
    }
    return QJsonObject{{QStringLiteral("format"), QStringLiteral("aster-studio")},
                       {QStringLiteral("version"), 2},
                       {QStringLiteral("rack"), rackJson(pluginStates)},
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
                       {QStringLiteral("lyrics"), QJsonObject{{QStringLiteral("text"), m_lyrics},
                                                             {QStringLiteral("start"), m_lyricsStart},
                                                             {QStringLiteral("bars"), m_lyricsBars},
                                                             {QStringLiteral("marks"), QJsonArray::fromVariantList(marks)}}},
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
    {
        const QJsonObject lo = o.value(QStringLiteral("lyrics")).toObject();
        m_lyrics = lo.value(QStringLiteral("text")).toString();
        m_lyricsStart = std::clamp(lo.value(QStringLiteral("start")).toInt(1), 1, 999);
        m_lyricsBars = std::clamp(lo.value(QStringLiteral("bars")).toInt(1), 1, 4);
        m_lyricMarks.clear();
        for (const QJsonValue &v : lo.value(QStringLiteral("marks")).toArray())
            m_lyricMarks << v.toDouble(-1);
        rebuildLyrics();
    }
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
    QHash<int, Slot> oldSlots;                  // cofanie: te same wtyczki grają dalej, bez ponownego wczytywania
    QHash<int, Channel> oldChannels;
    for (const Track &t : m_tracks)
        if (t.armed)
            armed << t.id;
    for (const Insert &in : m_inserts)
        for (const Slot &sl : in.slots_)
            oldSlots.insert(sl.id, sl);
    for (const Channel &c : m_channels)
        oldChannels.insert(c.id, c);
    m_tracks.clear();
    clearRack();
    QHash<int, QJsonObject> legacy;
    const QJsonObject rack = o.value(QStringLiteral("rack")).toObject();
    for (const QJsonValue &v : rack.value(QStringLiteral("inserts")).toArray()) {
        Insert in = insertFromJson(v.toObject(), oldSlots);
        m_nextId = std::max(m_nextId, in.id + 1);
        m_inserts.append(in);
    }
    for (const QJsonValue &tv : o.value(QStringLiteral("tracks")).toArray()) {
        const QJsonObject to = tv.toObject();
        Track t;
        t.id = to.value(QStringLiteral("id")).toInt();
        if (t.id <= 0)
            t.id = m_nextId++;
        m_nextId = std::max(m_nextId, t.id + 1);
        t.name = to.value(QStringLiteral("name")).toString();
        t.color = to.value(QStringLiteral("color")).toInt() % Colors;
        t.input = to.value(QStringLiteral("input")).toInt();
        t.beat = to.value(QStringLiteral("beat")).toBool();
        t.role = to.value(QStringLiteral("role")).toString();
        t.kind = to.value(QStringLiteral("kind")).toString(QStringLiteral("audio"));
        t.pattern = to.value(QStringLiteral("pattern")).toObject();
        t.armed = armed.contains(t.id);
        t.insert = to.value(QStringLiteral("insert")).toInt();
        // Projekt sprzed miksera: głośność i efekty były w ścieżce — każda dostaje własny insert
        if (!t.insert)
            legacy.insert(int(m_tracks.size()), to);
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
            for (const QJsonValue &v : co.value(QStringLiteral("takes")).toArray())
                c.takes.append(fr(v));
            c.take = c.takes.isEmpty() ? 0 : std::clamp(co.value(QStringLiteral("take")).toInt(), 0, int(c.takes.size()) - 1);
            c.origFile = co.value(QStringLiteral("origFile")).toString();
            c.pattern = co.value(QStringLiteral("pattern")).toInt();
            c.autoTarget = co.value(QStringLiteral("autoTarget")).toString();
            for (const QJsonValue &v : co.value(QStringLiteral("autoPoints")).toArray())
                c.autoPts.append({v.toArray().at(0).toDouble(), v.toArray().at(1).toDouble()});
            if ((c.file.isEmpty() && !c.pattern && c.autoTarget.isEmpty()) || c.length <= 0 || c.srcLen <= 0)
                continue;
            t.clips.append(c);
        }
        m_tracks.append(t);
    }
    for (auto it = legacy.constBegin(); it != legacy.constEnd(); ++it) {
        Insert in = insertFromJson(it.value(), oldSlots);
        in.id = m_nextId++;
        in.name = m_tracks[it.key()].name;
        in.color = m_tracks[it.key()].color;
        m_tracks[it.key()].insert = in.id;
        m_inserts.append(in);
    }
    rackFromJson(rack, oldChannels);
    for (int i = 0; i < m_tracks.size(); ++i)
        if (m_tracks[i].kind != QLatin1String("audio"))
            convertPatternTrack(i);
    m_selInsert = m_tracks.isEmpty() ? (m_inserts.isEmpty() ? 0 : m_inserts.first().id) : m_tracks[std::clamp(m_selTrack, 0, int(m_tracks.size()) - 1)].insert;
    if (!findChannel(m_selChannel))
        m_selChannel = m_channels.isEmpty() ? 0 : m_channels.first().id;
    if (!findPattern(m_curPattern))
        m_curPattern = m_patterns.isEmpty() ? 0 : m_patterns.first().id;
    emit settingsChanged();
    changed();
}

void Studio::checkpoint()
{
    if (!isOpen())
        return;
    m_undo.append(toJson(false));
    if (m_undo.size() > 100)
        m_undo.removeFirst();
    m_redo.clear();
    emit historyChanged();
}

void Studio::undo()
{
    if (m_undo.isEmpty() || recording())
        return;
    m_redo.append(toJson(false));
    const QString text = m_lyrics;
    const QList<double> marks = m_lyricMarks;
    const int ls = m_lyricsStart, lb = m_lyricsBars;
    fromJson(m_undo.takeLast());
    m_lyrics = text;
    m_lyricMarks = marks;
    m_lyricsStart = ls;
    m_lyricsBars = lb;
    rebuildLyrics();
    emit historyChanged();
}

void Studio::redo()
{
    if (m_redo.isEmpty() || recording())
        return;
    m_undo.append(toJson(false));
    const QString text = m_lyrics;
    const QList<double> marks = m_lyricMarks;
    const int ls = m_lyricsStart, lb = m_lyricsBars;
    fromJson(m_redo.takeLast());
    m_lyrics = text;
    m_lyricMarks = marks;
    m_lyricsStart = ls;
    m_lyricsBars = lb;
    rebuildLyrics();
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
                                     {QStringLiteral("takes"), int(c.takes.size())},
                                     {QStringLiteral("take"), c.take},
                                     {QStringLiteral("takeOk"), [&] {
                                          // Które podejścia obejmują ten kawałek (ostatnie bywa niepełne)
                                          QVariantList ok;
                                          for (long long v : c.takes) {
                                              const long long s0 = c.srcStart + v - c.takes.value(c.take);
                                              ok.append(src && s0 >= 0 && s0 + c.srcLen <= src->frames);
                                          }
                                          return ok;
                                      }()},
                                     {QStringLiteral("loop"), c.loop},
                                     {QStringLiteral("fadeIn"), c.fadeIn / R},
                                     {QStringLiteral("fadeOut"), c.fadeOut / R},
                                     {QStringLiteral("gain"), c.gain},
                                     {QStringLiteral("pattern"), c.pattern},
                                     {QStringLiteral("autoTarget"), c.autoTarget},
                                     {QStringLiteral("autoPoints"), [&] {
                                          QVariantList l;
                                          for (const QPointF &p : c.autoPts)
                                              l.append(QVariantMap{{QStringLiteral("t"), p.x() / R}, {QStringLiteral("v"), p.y()}});
                                          return l;
                                      }()},
                                     {QStringLiteral("missing"), !src && !c.pattern && c.autoTarget.isEmpty() && m_loading == 0}});
        }
        const Insert &in = ins(t);
        m_tracksView.append(QVariantMap{{QStringLiteral("id"), t.id},
                                        {QStringLiteral("name"), t.name},
                                        {QStringLiteral("color"), t.color},
                                        {QStringLiteral("volume"), in.volume},
                                        {QStringLiteral("pan"), in.pan},
                                        {QStringLiteral("mute"), in.mute},
                                        {QStringLiteral("solo"), in.solo},
                                        {QStringLiteral("insert"), t.insert},
                                        {QStringLiteral("armed"), t.armed},
                                        {QStringLiteral("input"), t.input},
                                        {QStringLiteral("kind"), t.kind},
                                        {QStringLiteral("beat"), t.beat},
                                        {QStringLiteral("role"), t.role},
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
    if (!findInsert(m_selInsert) && !m_inserts.isEmpty()) {
        m_selInsert = m_tracks.isEmpty() ? m_inserts.first().id : m_tracks.first().insert;
        emit selectionChanged();
    }
    updateMonitor();
    m_mixView.clear();
    for (const Track &tr : m_tracks) {
        const Insert &t = ins(tr);
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
                                     {QStringLiteral("double"), t.dbl},
                                     {QStringLiteral("deess"), t.deess},
                                     {QStringLiteral("denoise"), t.denoise},
                                     {QStringLiteral("plugins"), [&] {
                                          QVariantList l;
                                          for (const Slot &s : t.slots_)
                                              l.append(QVariantMap{{QStringLiteral("id"), s.id},
                                                                   {QStringLiteral("name"), s.info.name},
                                                                   {QStringLiteral("vendor"), s.info.vendor},
                                                                   {QStringLiteral("bypass"), s.bypass},
                                                                   {QStringLiteral("missing"), !s.plugin}});
                                          return l;
                                      }()},
                                     {QStringLiteral("preset"), t.preset}});
    }
    emit mixChanged();
    emit rackChanged();
}

Snapshot *Studio::buildSnapshot(bool forExport)
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
    // Solo: to, co ma solo, i wszystko, dokąd ono wysyła dźwięk
    QSet<int> soloed;
    for (const Insert &in : m_inserts)
        if (in.solo)
            soloed.insert(in.id);
    for (int round = 0; round < m_inserts.size(); ++round)
        for (const Insert &in : m_inserts)
            if (soloed.contains(in.id))
                for (const Send &sd : in.sends)
                    soloed.insert(sd.to);
    const bool anySolo = !soloed.isEmpty();
    for (const Insert &t : m_inserts) {
        InsertRT rt;
        rt.gain = float(dbToGain(t.volume));
        rt.pan = float(std::clamp(t.pan, -1.0, 1.0));
        rt.audible = anySolo ? soloed.contains(t.id) && !t.mute : !t.mute;
        rt.toMaster = t.toMaster;
        if (t.duckFrom) {
            rt.duckFrom = insertIndex(t.duckFrom);
            rt.duck = float(t.duck);
        }
        for (const Send &sd : t.sends)
            rt.sends.push_back({insertIndex(sd.to), float(dbToGain(sd.db))});
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
        rt.dbl = float(t.dbl);
        if (t.deess > 0.005) {
            rt.deess = float(t.deess);
            rt.deessLp = Biquad::lowPass(4500, R);
            rt.deessHp = Biquad::highPass(4500, R);
        }
        if (t.tune > 0.005) {
            static const int minor[7] = {0, 2, 3, 5, 7, 8, 10}, major[7] = {0, 2, 4, 5, 7, 9, 11};
            uint16_t mask = 0;
            for (int d = 0; d < 7; ++d)
                mask |= uint16_t(1u << ((m_keyRoot + (m_keyMinor ? minor[d] : major[d])) % 12));
            rt.tune.on = true;
            rt.tune.amount = float(t.tune);
            rt.tune.scale = mask;
        }
        for (const Slot &sl : t.slots_) {
            if (sl.bypass || !sl.plugin)
                continue;
            std::shared_ptr<Vst3::Plugin> p = sl.plugin;
            if (forExport) {
                Slot copy = sl;
                copy.state = sl.plugin->state();
                p = makePlugin(copy, true);
                if (!p)
                    continue;
            }
            s->plugins.push_back(p);
            rt.fx.push_back({p.get(), sl.side ? insertIndex(sl.side) : -1});
            m_snapPlugins.insert(sl.id, p.get());
        }
        s->inserts.push_back(std::move(rt));
    }
    for (int i : insertOrder())
        s->order.push_back(i);
    for (const Track &t : m_tracks) {
        LaneRT rt;
        rt.insert = insertIndex(t.insert);
        const bool punched = m_punchOut > m_punchIn && m_recTrack >= 0 && m_recTrack < m_tracks.size() && &t == &m_tracks[m_recTrack];
        for (const Clip &c : punched ? carved(t.clips, m_punchIn, m_punchOut, -1, nullptr) : t.clips) {
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
        if (!m_patMode)                         // WZÓR: gra tylko bieżący wzór
            s->lanes.push_back(std::move(rt));
    }
    // Zamrożone inserty: same pliki, bez źródeł i efektów
    for (const Insert &t : std::as_const(m_inserts)) {
        const SourcePtr src = t.frozen.isEmpty() ? nullptr : m_sources.value(t.frozen);
        if (!src)
            continue;
        const int at = insertIndex(t.id);
        InsertRT &rt = s->inserts[size_t(at)];
        InsertRT bare;
        bare.gain = rt.gain;
        bare.pan = rt.pan;
        bare.audible = rt.audible;
        bare.toMaster = rt.toMaster;
        bare.send = rt.send;
        bare.echo = rt.echo;
        bare.sends = rt.sends;
        rt = bare;
        for (LaneRT &lane : s->lanes)
            if (lane.insert == at)
                lane.clips.clear();
        s->keep.push_back(src);
        LaneRT lane;
        lane.insert = at;
        ClipRT c;
        c.src = src.get();
        c.length = c.srcLen = src->frames;
        c.raw = true;
        lane.clips.push_back(c);
        s->lanes.push_back(std::move(lane));
    }
    compileChannels(s, forExport);
    compileAutos(s);
    compileLatency(s);
    return s;
}

// Wczytuje pliki z audio/ w tle; po wczytaniu klipy dostają kształt fali i grają
void Studio::loadSources(const QStringList &all)
{
    QStringList files = all;
    files.removeAll(QString());                 // klipy wzorów nie mają pliku
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
    t.insert = newInsert(t.name, t.color);
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
    {
        // Insert ścieżki znika z nią, chyba że gra przez niego ktoś jeszcze
        const int id = m_tracks[index].insert;
        m_tracks.removeAt(index);
        bool used = std::any_of(m_tracks.begin(), m_tracks.end(), [id](const Track &t) { return t.insert == id; })
                    || std::any_of(m_channels.begin(), m_channels.end(), [id](const Channel &c) { return c.insert == id; });
        if (!used)
            removeInsert(id);
    }
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
    ins(index).volume = std::clamp(db, -60.0, 6.0);
    changed(false);
}

void Studio::setTrackPan(int index, double pan)
{
    if (index < 0 || index >= m_tracks.size())
        return;
    ins(index).pan = std::clamp(pan, -1.0, 1.0);
    changed(false);
}

void Studio::setTrackMute(int index, bool on)
{
    if (index < 0 || index >= m_tracks.size())
        return;
    ins(index).mute = on;
    changed(false);
}

void Studio::setTrackSolo(int index, bool on)
{
    if (index < 0 || index >= m_tracks.size())
        return;
    ins(index).solo = on;
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
    for (QPointF &p : c.autoPts)
        p.setX(p.x() - double(d));
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
    m_tracks[track].clips = carved(m_tracks[track].clips, a, b, keepId, &m_nextId);
}

// Klipy po wycięciu [a, b); nextId — numery dla klipów rozciętych na dwa (nullptr — bez nowych numerów, do migawki)
QList<Studio::Clip> Studio::carved(const QList<Clip> &clips, long long a, long long b, int keepId, int *nextId)
{
    QList<Clip> out;
    for (Clip c : clips) {
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
            if (cs < a && nextId)
                right.id = (*nextId)++;
            cutStart(right, b - cs);
            right.fadeIn = 0;
            out.append(right);
        }
    }
    return out;
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
                    t.insert = st->newInsert(t.name, t.color);
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

void Studio::importBeat(const QVariant &url)
{
    const QString path = localPath(url.toUrl().isValid() && !url.toUrl().scheme().isEmpty() ? url.toUrl().toString() : url.toString());
    if (!QFileInfo(path).isFile())
        return;
    if (!isOpen() && !newProject(QFileInfo(path).completeBaseName(), 140, 4, QStringLiteral("beat")))
        return;
    if (m_tracks.size() >= Renderer::MaxTracks) {
        emit message(QStringLiteral("Projekt może mieć najwyżej %1 ścieżki.").arg(Renderer::MaxTracks));
        return;
    }
    ++m_loading;
    emit busyChanged();
    emit message(QStringLiteral("Słucham bitu — rozpoznaję tempo i tonację…"));
    const QFileInfo fi(path);
    const QString dir = m_folder + QStringLiteral("/audio/");
    const QString target = fi.absolutePath() + QLatin1Char('/') == dir ? path : uniqueAudioPath(fi.completeBaseName(), fi.suffix().toLower());
    QPointer<Studio> self(this);
    QThreadPool::globalInstance()->start([self, path, target, dir, name = fi.completeBaseName()] {
        QString err;
        auto src = loadAudio(path, Engine::Rate, &err);
        Analysis::Result an;
        if (src) {
            if (target != path && !QFile::copy(path, target))
                err = QStringLiteral("Nie udało się skopiować „%1” do projektu.").arg(QFileInfo(path).fileName()), src.reset();
            else {
                src->file = QFileInfo(target).fileName();
                an = Analysis::analyze(*src, Engine::Rate);
            }
        }
        QMetaObject::invokeMethod(qApp, [self, src, an, err, dir, name] {
            if (!self)
                return;
            Studio *st = self;
            --st->m_loading;
            emit st->busyChanged();
            if (!src) {
                emit st->message(err);
                return;
            }
            if (st->m_folder + QStringLiteral("/audio/") != dir)
                return;
            st->checkpoint();
            st->m_sources.insert(src->file, src);
            // Tempo i tonacja projektu jak w bicie (ścieżki wzorów idą za tempem)
            if (an.bpm > 0) {
                st->setBpm(an.bpm);
            }
            if (an.keyRoot >= 0) {
                st->m_keyRoot = an.keyRoot;
                st->m_keyMinor = an.minor;
            }
            Track t;
            t.id = st->m_nextId++;
            t.name = QStringLiteral("Bit");
            t.beat = true;
            QList<int> used;
            for (const Track &o : st->m_tracks)
                used << o.color;
            t.color = int(st->m_tracks.size()) % Colors;
            for (int c = 0; c < Colors; ++c)
                if (!used.contains(c)) {
                    t.color = c;
                    break;
                }
            Clip c;
            c.id = st->m_nextId++;
            c.file = src->file;
            c.name = name;
            c.length = c.srcLen = src->frames;
            // Pierwszy „raz” bitu na początku taktu: cisza przed nim — przycięta; dźwięk przed nim
            // (przedtakt) — cały bit przesunięty tak, że „raz” wypada na początku taktu 2
            if (an.bpm > 0 && an.firstBar > 0.02) {
                const long long fb = llround(an.firstBar * Engine::Rate);
                if (an.leadIn >= an.firstBar - 0.03)
                    cutStart(c, fb), c.start = 0;
                else
                    c.start = llround(st->m_beatsPerBar * 60.0 / st->m_bpm * Engine::Rate) - fb;
            }
            t.clips.append(c);
            t.insert = st->newInsert(t.name, t.color);
            st->m_inserts.last().volume = -3;       // gotowe bity są głośne — zostaje miejsce na głos
            st->m_tracks.append(t);
            st->m_selTrack = int(st->m_tracks.size()) - 1;
            st->m_selClip = c.id;
            ++st->m_sourcesVersion;
            emit st->sourcesChanged();
            emit st->settingsChanged();
            emit st->selectionChanged();
            st->changed();
            QString msg = an.bpm > 0 ? QStringLiteral("Bit: %1 BPM").arg(QLocale().toString(an.bpm, 'g', 4))
                                     : QStringLiteral("Bit dodany — tempa nie udało się rozpoznać, ustaw je ręcznie");
            if (an.keyRoot >= 0)
                msg += QStringLiteral(", %1").arg(st->keyName()) + (an.keyConfidence < 0.3 ? QStringLiteral(" (sprawdź tonację w zakładce Piosenka)") : QString());
            if (an.bpm > 0)
                msg += QStringLiteral(" — siatka taktów i autotune pasują do bitu");
            emit st->message(msg);
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
    setPatternMode(false);                      // nagranie idzie na playlistę
    // Ścieżka: ta gotowa do nagrania, a gdy żadna nie jest — zaznaczona (albo nowa)
    int ti = -1;
    for (int i = 0; i < m_tracks.size(); ++i)
        if (m_tracks[i].armed)
            ti = i;
    if (ti < 0) {
        // Zaznaczona ścieżka nagrania, a gdy zaznaczony jest bit — pierwsza ścieżka nagrania (albo nowa)
        ti = std::clamp(m_selTrack, 0, int(m_tracks.size()) - 1);
        if (ti < 0 || m_tracks[ti].kind != QLatin1String("audio") || m_tracks[ti].beat) {
            ti = -1;
            for (int i = 0; i < m_tracks.size() && ti < 0; ++i)
                if (m_tracks[i].kind == QLatin1String("audio") && !m_tracks[i].beat)
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
    updateMonitor();
    m_recPath = uniqueAudioPath(m_tracks[ti].name, QStringLiteral("wav"));
    m_recLoopStart = m_recLoopEnd = 0;
    m_punchIn = m_punchOut = 0;
    const bool region = m_cycleEnd - m_cycleStart > 0.25;
    const double bar = m_beatsPerBar * 60.0 / m_bpm;
    long long start = frames(m_position), from = start - (m_countIn ? llround(bar * Engine::Rate) : 0);
    long long countInEnd = m_countIn ? start : Engine::NoSeek;
    if (m_punch && region) {
        // Wymiana fragmentu: rozbieg z bitem i dotychczasowym nagraniem (ok. 3 s, pełne takty), w regionie
        // stare milknie. Nagrywa się też rozbieg — klip da się potem wydłużyć w lewo
        m_punchIn = frames(m_cycleStart);
        m_punchOut = frames(m_cycleEnd);
        const int bars = std::clamp(int(std::ceil(3.0 / bar - 0.01)), 1, 4);
        from = m_punchIn - llround(bars * bar * Engine::Rate);
        start = std::max(0LL, from);
        countInEnd = from < 0 ? 0 : Engine::NoSeek;      // przed początkiem piosenki — metronom
        m_engine.setCycle(false, 0, 0);                  // bez zawracania: jedno przejście
    } else if (m_cycle && region) {
        // Pętla włączona: nagrywanie od jej początku, każde przejście to nowe podejście
        m_recLoopStart = frames(m_cycleStart);
        m_recLoopEnd = frames(m_cycleEnd);
        start = m_recLoopStart;
        from = start - (m_countIn ? llround(bar * Engine::Rate) : 0);
        countInEnd = m_countIn ? start : Engine::NoSeek;
    }
    if (!m_engine.startRecording(m_recPath, start, m_tracks[ti].input)) {
        m_punchIn = m_punchOut = 0;
        m_engine.setCycle(m_cycle, frames(m_cycleStart), frames(m_cycleEnd));
        emit message(QStringLiteral("Nie ma wejścia dźwięku — podłącz mikrofon i wybierz go w ustawieniach dźwięku."));
        return;
    }
    if (m_punchOut > m_punchIn)
        m_engine.setSnapshot(buildSnapshot());          // stare nagranie w regionie wyciszone
    m_engine.play(from, countInEnd);
    m_position = double(from) / Engine::Rate;
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
    const long long pin = m_punchIn, pout = m_punchOut;
    if (pout > pin) {
        m_punchIn = m_punchOut = 0;
        m_engine.setCycle(m_cycle, frames(m_cycleStart), frames(m_cycleEnd));
        m_engine.setSnapshot(buildSnapshot());          // stare nagranie znów gra w całości
    }
    emit transportChanged();
    // Wymiana fragmentu: z nagrania zostaje region i po 10 ms z obu stron na przenikanie ze starym
    const long long xf = Engine::Rate / 100;
    const long long pa = std::max(start, pin - xf);
    const long long pb = src ? std::min(start + src->frames, pout + xf) : 0;
    const bool missed = pout > pin && src && pb - pa < Engine::Rate / 10;
    if (!src || src->frames < Engine::Rate / 20 || ti < 0 || ti >= m_tracks.size() || missed) {
        QFile::remove(m_recPath);
        if (!src)
            emit message(QStringLiteral("Nic się nie nagrało — sprawdź mikrofon w ustawieniach dźwięku."));
        else if (missed)
            emit message(QStringLiteral("Nagrywanie skończyło się przed fragmentem do wymiany — nic się nie zmieniło."));
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
    const long long cs = m_recLoopStart, ce = m_recLoopEnd, len = ce - cs;
    int passes = 1;
    if (len > 0 && start < ce && start + src->frames > ce + Engine::Rate / 4) {
        // Nagrywanie w pętli: przejście 0 to [start, ce), kolejne zaczynają się w pliku co len.
        // Klip na całym regionie pętli; domyślnie ostatnie pełne podejście
        const long long first = ce - start;
        passes = 1 + int((src->frames - first + len - 1) / len);
        QList<long long> at;                    // gdzie w pliku jest początek regionu (cs) w podejściu k
        for (int k = 0; k < passes; ++k)
            at.append(k == 0 ? cs - start : first + (k - 1) * len);
        int best = 0;
        for (int k = passes - 1; k > 0; --k)
            if (at[k] + len <= src->frames) {
                best = k;
                break;
            }
        for (int k = 0; k < passes; ++k)
            c.takes.append(at[k] - at[0]);
        c.take = best;
        c.start = best == 0 ? std::max(cs, start) : cs;
        c.srcStart = at[best] + (c.start - cs);
        c.length = c.srcLen = ce - c.start;
    }
    if (pout > pin) {
        c.name = m_tracks[ti].name;
        for (const Clip &o : std::as_const(m_tracks[ti].clips))
            if (o.start < pout && o.start + o.length > pin)
                c.name = m_tracks[ti].name + QStringLiteral(" — poprawka");
        c.start = pa;
        c.srcStart = pa - start;
        c.length = c.srcLen = pb - pa;
        c.fadeIn = pa < pin ? pin - pa : 0;
        c.fadeOut = pb > pout ? pb - pout : 0;
        // Zatrzymane w środku regionu — dalej zostaje stare nagranie, nowe w nie przechodzi
        carve(ti, std::max(pin, pa), pb >= pout + xf ? pout : std::max(pin, pb - xf), 0);
    } else {
        carve(ti, c.start, c.start + c.length, 0);
    }
    m_tracks[ti].clips.append(c);
    m_selClip = c.id;
    emit selectionChanged();
    changed();
    save();          // nagrania nie giną, nawet gdy program się zamknie
    // Ścieżka z odszumianiem: nowe nagranie też (w tle, bez osobnego kroku do cofania)
    if (ins(ti).denoise > 0)
        startDenoise(m_tracks[ti].id, {{c.file, c.file}}, ins(ti).denoise, true);
    if (passes > 1)
        emit message(QStringLiteral("Nagrane podejścia: %1 — wybierz najlepsze w zakładce Klip albo pod prawym przyciskiem. "
                                    "Podziel klip (S), żeby z każdego kawałka wziąć inne.").arg(passes));
}

void Studio::setClipTake(int id, int take)
{
    Clip *c = findClip(id);
    if (!c || take < 0 || take >= c->takes.size() || take == c->take)
        return;
    const SourcePtr src = m_sources.value(c->file);
    const long long s = c->srcStart + c->takes[take] - c->takes[c->take];
    if (!src || s < 0 || s + c->srcLen > src->frames) {
        emit message(QStringLiteral("Podejście %1 nie obejmuje tego fragmentu — nagrywanie skończyło się wcześniej.").arg(take + 1));
        return;
    }
    checkpoint();
    c->srcStart = s;
    c->take = take;
    changed();
}

int Studio::recordTake() const
{
    const long long len = m_recLoopEnd - m_recLoopStart;
    if (!recording() || len <= 0)
        return 0;
    const long long first = m_recLoopEnd - m_engine.recordStart(), f = m_engine.recordedFrames();
    return f < first ? 1 : 2 + int((f - first) / len);
}

double Studio::recordTakeOffset() const
{
    const int k = recordTake();
    if (k <= 1)
        return 0;
    return double(m_recLoopEnd - m_engine.recordStart() + (k - 2) * (m_recLoopEnd - m_recLoopStart)) / Engine::Rate;
}

void Studio::tick()
{
    m_engine.collect();
    {
        // Wtyczka może zmienić opóźnienie (np. tryb wysokiej jakości) — wyrównanie liczy się od nowa
        int sum = 0;
        for (const Insert &in : std::as_const(m_inserts))
            for (const Slot &sl : in.slots_)
                if (sl.plugin && !sl.bypass)
                    sum += sl.plugin->latency();
        if (sum != m_lastLatency) {
            m_lastLatency = sum;
            m_engine.setSnapshot(buildSnapshot());
        }
    }
    // Wymiana fragmentu: po regionie i krótkim wybrzmieniu nagrywanie kończy się samo
    if (recording() && m_punchOut > m_punchIn && m_engine.position() > m_punchOut + Engine::Rate * 3 / 4) {
        finishRecording();
        return;
    }
    if (playing()) {
        const double pos = double(m_engine.position()) / Engine::Rate;
        if (pos != m_position) {
            m_position = pos;
            emit positionChanged();
        }
    }
    // Wskaźniki: szczyt z opadaniem
    std::vector<float> peaks(size_t(m_inserts.size()), 0.f);
    float master[2], in[2];
    m_engine.readMeters(peaks, master);
    m_engine.readInputLevel(in);
    bool moving = false;
    while (m_insLevels.size() < m_inserts.size())
        m_insLevels.append(0.0);
    while (m_insLevels.size() > m_inserts.size())
        m_insLevels.removeLast();
    auto fall = [&moving](double old, double v) {
        const double r = std::max(v, old * 0.82);
        const double out = r < 0.001 ? 0.0 : r;
        moving |= out != old;
        return out;
    };
    for (int i = 0; i < m_levels.size() && i < m_tracks.size(); ++i) {
        const int at = insertIndex(m_tracks[i].insert);
        m_levels[i] = fall(m_levels[i].toDouble(), at >= 0 && at < int(peaks.size()) ? peaks[size_t(at)] : 0.f);
    }
    for (int i = 0; i < m_insLevels.size(); ++i)
        m_insLevels[i] = fall(m_insLevels[i].toDouble(), peaks[size_t(i)]);
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
    const QString ext = format == QLatin1String("mp3") || format == QLatin1String("ogg") || format == QLatin1String("flac") ? format : QStringLiteral("wav");
    QDir().mkpath(m_folder + QStringLiteral("/Eksport"));
    startExport(ext, m_folder + QStringLiteral("/Eksport/") + m_name + QLatin1Char('.') + ext, {});
}

void Studio::startExport(const QString &ext, const QString &path, ExportDone done)
{
    if (!isOpen() || m_exporting)
        return;
    const long long end = frames(duration());
    if (end <= 0) {
        const QString err = QStringLiteral("Projekt jest pusty — nagraj albo dodaj dźwięk.");
        if (done)
            done(false, QString(), err);
        else
            emit exportFinished(false, QString(), err);
        return;
    }
    std::shared_ptr<Snapshot> snap(buildSnapshot(true));
    m_exporting = true;
    m_exportProgress = 0;
    m_exportShared.store(0);
    m_cancelExport.store(false);
    emit exportChanged();
    // Na wybrzmienie: pół sekundy, a z pogłosem — tyle, ile wybrzmiewa sala
    bool reverb = false;
    for (const Insert &t : m_inserts)
        reverb |= t.reverb > 0 && !t.mute;
    const long long total = end + llround(Engine::Rate * (reverb ? 1.5 + 3.0 * m_reverbSize : 0.5));
    QPointer<Studio> self(this);
    QThreadPool::globalInstance()->start([self, snap, total, path, ext, done, this] {
        QString err;
        const bool ok = Engine::exportMix(*snap, total, path, ext, [this](double p) {
            m_exportShared.store(p);
            return !m_cancelExport.load();
        }, &err);
        QMetaObject::invokeMethod(qApp, [self, ok, path, err, done] {
            if (!self)
                return;
            self->m_exporting = false;
            emit self->exportChanged();
            const QString msg = ok || err.isEmpty() ? err : QStringLiteral("Nie udało się zapisać miksu: ") + err;
            if (done)
                done(ok, path, msg);
            else
                emit self->exportFinished(ok, path, msg);
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

void Studio::applyPresetTo(Insert &t, const QString &preset)
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
        // Jasne wokale syczą — de-esser od razu w gotowym brzmieniu głosu
        t.deess = QString::fromLatin1(p.group) == QLatin1String("Wokal") ? 0.4 : 0;
        t.preset = preset == QLatin1String("none") ? QString() : preset;
    }
}

void Studio::applyPreset(int index, const QString &preset)
{
    if (index < 0 || index >= m_tracks.size())
        return;
    checkpoint();
    applyPresetTo(ins(index), preset);
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
    if (index >= 0 && index < m_tracks.size())
        setInsertFx(m_tracks[index].insert, key, value);
}

void Studio::setInsertFx(int id, const QString &key, double value)
{
    Insert *strip = findInsert(id);
    if (!strip)
        return;
    Insert &t = *strip;
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
    else if (key == QLatin1String("double"))
        t.dbl = std::clamp(value, 0.0, 1.0);
    else if (key == QLatin1String("deess"))
        t.deess = std::clamp(value, 0.0, 1.0);
    else
        return;
    if (key != QLatin1String("double") && key != QLatin1String("deess"))
        t.preset.clear();           // ręczna zmiana — już nie gotowe ustawienie (sztucznego dubla gotowe brzmienia nie ustawiają)
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

// ——— Wtyczki VST3 ———

QVariantList Studio::plugins() const
{
    QVariantList l;
    for (const Vst3::Info &i : m_pluginList)
        l.append(QVariantMap{{QStringLiteral("uid"), i.uid},
                             {QStringLiteral("name"), i.name},
                             {QStringLiteral("vendor"), i.vendor},
                             {QStringLiteral("category"), i.category},
                             {QStringLiteral("instrument"), i.instrument}});
    return l;
}

void Studio::scanPlugins()
{
    m_pluginList = Vst3::scan();
    m_pluginsScanned = true;
    emit pluginsChanged();
}

std::shared_ptr<Vst3::Plugin> Studio::makePlugin(const Slot &s, bool applyState)
{
    QString err;
    std::shared_ptr<Vst3::Plugin> p = Vst3::Plugin::load(s.info, Engine::Rate, Renderer::MaxBlock, &err);
    if (p && applyState && !s.state.isEmpty())
        p->setState(s.state);
    return p;
}

void Studio::addPlugin(int insert, const QString &uid)
{
    Insert *in = findInsert(insert);
    if (!in)
        return;
    for (const Vst3::Info &i : std::as_const(m_pluginList)) {
        if (i.uid != uid)
            continue;
        if (i.instrument) {
            emit message(QStringLiteral("„%1” to instrument — dodaj go jako kanał w racku.").arg(i.name));
            return;
        }
        checkpoint();
        Slot s;
        s.id = m_nextId++;
        s.info = i;
        s.plugin = makePlugin(s, false);
        if (!s.plugin) {
            emit message(QStringLiteral("Wtyczka „%1” nie chce się uruchomić.").arg(i.name));
            return;
        }
        findInsert(insert)->slots_.append(s);
        changed(false);
        s.plugin->openEditor();
        return;
    }
}

void Studio::removePlugin(int insert, int slot)
{
    Insert *in = findInsert(insert);
    if (!in)
        return;
    for (int i = 0; i < in->slots_.size(); ++i) {
        if (in->slots_[i].id != slot)
            continue;
        checkpoint();
        in = findInsert(insert);
        if (in->slots_[i].plugin) {
            in->slots_[i].plugin->closeEditor();
            m_slotMemo.insert(slot, in->slots_[i].plugin->state());
        }
        in->slots_.removeAt(i);
        changed(false);
        return;
    }
}

void Studio::setPluginBypass(int insert, int slot, bool on)
{
    if (Insert *in = findInsert(insert))
        for (Slot &s : in->slots_)
            if (s.id == slot) {
                s.bypass = on;
                changed(false);
            }
}

void Studio::openPlugin(int insert, int slot)
{
    if (Insert *in = findInsert(insert))
        for (Slot &s : in->slots_)
            if (s.id == slot && s.plugin && !s.plugin->openEditor())
                emit message(QStringLiteral("Okno wtyczki „%1” się nie otworzyło (wymaga XWayland).").arg(s.info.name));
}

// ——— Odszumianie ———

void Studio::denoiseTrack(int index, int level)
{
    if (index < 0 || index >= m_tracks.size() || recording() || m_tracks[index].kind != QLatin1String("audio"))
        return;
    level = std::clamp(level, 0, 3);
    Track &t = m_tracks[index];
    if (level == 0) {
        // Z powrotem oryginały
        checkpoint();
        QStringList missing;
        for (Clip &c : t.clips) {
            if (c.origFile.isEmpty())
                continue;
            c.file = c.origFile;
            c.origFile.clear();
            if (!m_sources.contains(c.file) && !missing.contains(c.file))
                missing << c.file;
        }
        ins(t).denoise = 0;
        changed();
        loadSources(missing);
        return;
    }
    QHash<QString, QString> files;
    for (const Clip &c : std::as_const(t.clips))
        if (!c.file.isEmpty())
            files.insert(c.file, c.origFile.isEmpty() ? c.file : c.origFile);
    if (files.isEmpty()) {
        // Nic jeszcze nie nagrano — ustawienie zadziała na nowych nagraniach
        ins(t).denoise = level;
        changed(false);
        emit message(QStringLiteral("Nowe nagrania na tej ścieżce będą od razu odszumiane."));
        return;
    }
    startDenoise(t.id, files, level, false);
}

void Studio::startDenoise(int trackId, const QHash<QString, QString> &files, int level, bool quiet)
{
    // Wynik zależy tylko od oryginału i siły — ten sam plik nie liczy się drugi raz
    QHash<QString, QString> outputs;           // oryginał → odszumiony
    QHash<QString, SourcePtr> ready;           // oryginały już w pamięci
    for (const QString &orig : files) {
        outputs.insert(orig, QFileInfo(orig).completeBaseName() + QStringLiteral(" · odszumione %1.wav").arg(level));
        if (const SourcePtr s = m_sources.value(orig))
            ready.insert(orig, s);
    }
    ++m_loading;
    emit busyChanged();
    const QString dir = m_folder + QStringLiteral("/audio/");
    QPointer<Studio> self(this);
    QThreadPool::globalInstance()->start([self, files, outputs, ready, dir, level, trackId, quiet] {
        QHash<QString, SourcePtr> made;
        QString error;
        for (auto it = outputs.begin(); it != outputs.end(); ++it) {
            const QString out = dir + it.value();
            std::shared_ptr<AudioSource> res;
            if (QFileInfo::exists(out))
                res = loadAudio(out, Engine::Rate, &error);
            if (!res) {
                SourcePtr in = ready.value(it.key());
                if (!in)
                    in = loadAudio(dir + it.key(), Engine::Rate, &error);
                if (!in)
                    continue;
                res = Denoise::process(*in, level);
                if (!res || !Denoise::saveWav(*res, out)) {
                    error = QStringLiteral("Nie udało się odszumić „%1” — nagranie jest za krótkie albo brak miejsca na dysku.").arg(it.key());
                    continue;
                }
            }
            res->file = it.value();
            made.insert(it.key(), res);
        }
        QMetaObject::invokeMethod(qApp, [self, files, made, error, dir, level, trackId, quiet] {
            if (!self)
                return;
            --self->m_loading;
            emit self->busyChanged();
            if (self->m_folder + QStringLiteral("/audio/") != dir)
                return;
            Track *t = nullptr;
            for (Track &x : self->m_tracks)
                if (x.id == trackId)
                    t = &x;
            if (!t || made.isEmpty()) {
                if (!error.isEmpty())
                    emit self->message(error);
                return;
            }
            if (!quiet)
                self->checkpoint();
            for (const SourcePtr &s : made)
                self->m_sources.insert(s->file, s);
            int n = 0;
            for (Clip &c : t->clips) {
                const auto it = files.find(c.file);
                if (it == files.end() || !made.contains(it.value()))
                    continue;
                c.origFile = it.value();
                c.file = made.value(it.value())->file;
                ++n;
            }
            self->ins(*t).denoise = level;
            ++self->m_sourcesVersion;
            emit self->sourcesChanged();
            self->changed();
            self->save();
            if (!quiet)
                emit self->message(n == 1 ? QStringLiteral("Nagranie odszumione — szum tła ściszony, głos został.")
                                          : QStringLiteral("Odszumione nagrania: %1 — szum tła ściszony, głos został.").arg(n));
            else if (!error.isEmpty())
                emit self->message(error);
        });
    });
}

// ——— Tekst piosenki ———

void Studio::resetLyrics()
{
    m_lyrics.clear();
    m_lyricMarks.clear();
    m_lyricsStart = m_lyricsBars = 1;
    rebuildLyrics();
}

void Studio::setLyrics(const QString &text)
{
    if (text == m_lyrics)
        return;
    // Znaczniki idą za wersami: ta sama liczba wierszy — po numerze (poprawka literówki),
    // inaczej po treści wiersza (dopisany albo usunięty wers przesuwa resztę)
    const QStringList before = m_lyrics.split(QLatin1Char('\n')), after = text.split(QLatin1Char('\n'));
    QList<double> marks(after.size(), -1);
    if (before.size() == after.size()) {
        for (int i = 0; i < after.size() && i < m_lyricMarks.size(); ++i)
            marks[i] = m_lyricMarks[i];
    } else {
        QHash<QString, QList<double>> byText;
        for (int i = 0; i < before.size() && i < m_lyricMarks.size(); ++i)
            if (m_lyricMarks[i] >= 0)
                byText[before[i].trimmed()] << m_lyricMarks[i];
        for (int i = 0; i < after.size(); ++i) {
            auto it = byText.find(after[i].trimmed());
            if (it != byText.end() && !it->isEmpty())
                marks[i] = it->takeFirst();
        }
    }
    m_lyrics = text;
    m_lyricMarks = marks;
    rebuildLyrics();
    setDirty(true);
}

void Studio::setLyricsStart(int bar)
{
    bar = std::clamp(bar, 1, 999);
    if (bar == m_lyricsStart)
        return;
    m_lyricsStart = bar;
    rebuildLyrics();
    setDirty(true);
}

void Studio::setLyricsBars(int bars)
{
    bars = std::clamp(bars, 1, 4);
    if (bars == m_lyricsBars)
        return;
    m_lyricsBars = bars;
    rebuildLyrics();
    setDirty(true);
}

void Studio::markLyric(int line, double seconds)
{
    if (line < 0 || line >= m_lyrics.count(QLatin1Char('\n')) + 1)
        return;
    while (m_lyricMarks.size() <= line)
        m_lyricMarks << -1;
    // W miarach, żeby tekst szedł za zmianą tempa; do szesnastki — drobne spóźnienie palca znika
    m_lyricMarks[line] = seconds < 0 ? -1 : std::round(seconds * m_bpm / 60.0 * 4) / 4;
    rebuildLyrics();
    setDirty(true);
}

void Studio::clearLyricMarks()
{
    if (std::none_of(m_lyricMarks.begin(), m_lyricMarks.end(), [](double m) { return m >= 0; }))
        return;
    m_lyricMarks.clear();
    rebuildLyrics();
    setDirty(true);
}

int Studio::lyricAt(double seconds) const
{
    // Wers pokazuje się chwilę wcześniej — oko wyprzedza głos
    const double beat = (seconds + 0.15) * m_bpm / 60.0;
    int cur = -1;
    double best = -1;
    for (const QVariant &v : m_lyricView) {
        const QVariantMap m = v.toMap();
        const double b = m.value(QStringLiteral("beat")).toDouble();
        if (b >= 0 && b <= beat && b >= best) {
            best = b;
            cur = m.value(QStringLiteral("line")).toInt();
        }
    }
    return cur;
}

// Widok dla QML: każdy wiersz z rodzajem, początkiem i końcem (miary), numerem taktu i rymem
void Studio::rebuildLyrics()
{
    const QStringList lines = m_lyrics.isEmpty() ? QStringList() : m_lyrics.split(QLatin1Char('\n'));
    const QList<Lyrics::Line> info = Lyrics::analyze(lines);
    const double step = double(m_lyricsBars) * m_beatsPerBar;
    QList<double> begin(lines.size(), -1);
    double next = double(m_lyricsStart - 1) * m_beatsPerBar;
    for (int i = 0; i < lines.size(); ++i) {
        if (info[i].kind != Lyrics::Kind::Line)
            continue;
        const double m = i < m_lyricMarks.size() ? m_lyricMarks[i] : -1;
        begin[i] = m >= 0 ? m : next;
        next = begin[i] + step;
    }
    m_lyricView.clear();
    int content = 0;
    for (int i = 0; i < lines.size(); ++i) {
        double end = -1;
        if (begin[i] >= 0) {
            end = begin[i] + step;
            for (int j = i + 1; j < lines.size(); ++j)
                if (begin[j] >= 0) {
                    end = begin[j] > begin[i] ? begin[j] : end;
                    break;
                }
        }
        const Lyrics::Line &l = info[i];
        m_lyricView.append(QVariantMap{
            {QStringLiteral("line"), i},
            {QStringLiteral("text"), lines[i]},
            {QStringLiteral("kind"), l.kind == Lyrics::Kind::Line ? QStringLiteral("line") : l.kind == Lyrics::Kind::Head ? QStringLiteral("head") : QStringLiteral("blank")},
            {QStringLiteral("index"), l.kind == Lyrics::Kind::Line ? content++ : -1},
            {QStringLiteral("beat"), begin[i]},
            {QStringLiteral("end"), end},
            {QStringLiteral("bar"), begin[i] >= 0 ? int(std::floor(begin[i] / m_beatsPerBar)) + 1 : 0},
            {QStringLiteral("marked"), i < m_lyricMarks.size() && m_lyricMarks[i] >= 0},
            {QStringLiteral("rhyme"), l.rhyme},
            {QStringLiteral("rhymeAt"), l.rhymeAt},
            {QStringLiteral("exact"), l.exact}});
    }
    emit lyricsChanged();
}

void Studio::setPunch(bool on)
{
    if (on == m_punch || recording())
        return;
    if (on && m_cycleEnd - m_cycleStart < 0.25) {
        // Bez regionu: zaznaczony klip, a gdy go nie ma — dwa takty od taktu z głowicą (pętla się nie włącza)
        if (const Clip *c = findClip(m_selClip)) {
            m_cycleStart = double(c->start) / Engine::Rate;
            m_cycleEnd = double(c->start + c->length) / Engine::Rate;
        } else {
            const double bar = 60.0 / m_bpm * m_beatsPerBar;
            m_cycleStart = std::floor(std::max(0.0, m_position) / bar) * bar;
            m_cycleEnd = m_cycleStart + 2 * bar;
        }
        m_engine.setCycle(m_cycle, frames(m_cycleStart), frames(m_cycleEnd));
        setDirty(true);
    }
    m_punch = on;
    emit cycleChanged();
}

namespace {
struct VocalRole
{
    const char *id, *name, *preset;
    double pan, volume;
};
const VocalRole s_roles[] = {
    {"main", "Wokal", "rap", 0, 0},
    {"double", "Dubel", "backing", -0.25, 0},
    {"adlib", "Ad-libsy", "radio", 0.3, -3},
};
}

int Studio::vocalTrack(const QString &role)
{
    if (!isOpen() || recording())
        return -1;
    const VocalRole *r = nullptr;
    for (const VocalRole &v : s_roles)
        if (role == QLatin1String(v.id))
            r = &v;
    if (!r)
        return -1;
    auto vocal = [this](int i) { return m_tracks[i].kind == QLatin1String("audio") && !m_tracks[i].beat; };
    int ti = -1;
    for (int i = 0; i < m_tracks.size() && ti < 0; ++i)
        if (vocal(i) && m_tracks[i].role == role)
            ti = i;
    // Starsze projekty bez ról: po nazwie (Dubel / Wokal 2, Ad-lib…), wokal — pierwsza ścieżka nagrań bez roli
    for (int i = 0; i < m_tracks.size() && ti < 0; ++i) {
        if (!vocal(i) || !m_tracks[i].role.isEmpty())
            continue;
        const QString n = m_tracks[i].name.toLower();
        const bool dbl = n.startsWith(QLatin1String("dubel")) || n == QLatin1String("wokal 2");
        const bool adl = n.startsWith(QLatin1String("ad-lib")) || n.startsWith(QLatin1String("adlib"));
        if ((role == QLatin1String("double") && dbl) || (role == QLatin1String("adlib") && adl) || (role == QLatin1String("main") && !dbl && !adl))
            ti = i;
    }
    if (ti >= 0) {
        m_tracks[ti].role = role;
    } else {
        addTrack(QString::fromUtf8(r->name));
        if (m_tracks.size() == 0 || m_tracks.last().name != QString::fromUtf8(r->name))
            return -1;                              // za dużo ścieżek
        ti = int(m_tracks.size()) - 1;
        Track &t = m_tracks[ti];
        Insert &strip = ins(t);
        applyPresetTo(strip, QString::fromLatin1(r->preset));
        strip.pan = r->pan;
        strip.volume = r->volume;
        t.role = role;
        changed(false);
    }
    setTrackArmed(ti, true);
    return ti;
}

void Studio::recordOver(int clipId, const QString &role)
{
    const Clip *c = findClip(clipId);
    if (!c || recording())
        return;
    const double a = double(c->start) / Engine::Rate, b = double(c->start + c->length) / Engine::Rate;
    if (vocalTrack(role) < 0)
        return;
    if (playing())
        m_engine.stop();
    m_cycleStart = a;
    m_cycleEnd = b;
    m_engine.setCycle(m_cycle, frames(a), frames(b));
    m_punch = true;
    emit cycleChanged();
    setDirty(true);
    m_position = a;
    record();
    if (recording())
        emit message(role == QLatin1String("double")
                         ? QStringLiteral("Dubel: rapuj to samo, co w zwrotce, słowo w słowo. Rozbieg słychać z bitem i głównym wokalem.")
                         : QStringLiteral("Ad-libsy: dorzucaj okrzyki i powtórzenia między wersami — nagrywa się tylko w tym fragmencie."));
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
    return kind == QLatin1String("bass") ? BeatSynth::Bass : kind == QLatin1String("keys") ? BeatSynth::Keys
         : kind == QLatin1String("melody") ? BeatSynth::Melody : BeatSynth::Drums;
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
    addTrack(k == BeatSynth::Bass ? QStringLiteral("808") : k == BeatSynth::Keys ? QStringLiteral("Akordy")
             : k == BeatSynth::Melody ? QStringLiteral("Melodia") : QStringLiteral("Bit"));   // zapamiętuje stan do cofnięcia
    Track &t = m_tracks.last();
    t.kind = k == BeatSynth::Bass ? QStringLiteral("bass") : k == BeatSynth::Keys ? QStringLiteral("keys")
           : k == BeatSynth::Melody ? QStringLiteral("melody") : QStringLiteral("drums");
    t.pattern = BeatSynth::genrePattern(genre.isEmpty() ? QStringLiteral("trap") : genre, k);
    applyPresetTo(ins(t), k == BeatSynth::Bass ? QStringLiteral("808") : k == BeatSynth::Keys || k == BeatSynth::Melody ? QStringLiteral("keys") : QStringLiteral("drums"));
    if (k == BeatSynth::Keys && genre == QLatin1String("trap"))
        ins(t).echo = 0.25;                     // dzwonki w trapie z echem
    if (k == BeatSynth::Bass) {
        m_keyRoot = std::clamp(t.pattern.value(QStringLiteral("root")).toInt(), 0, 11);       // tonacja jak bas: akordy idą za nią
        m_keyMinor = true;
        emit settingsChanged();
    }
    convertPatternTrack(int(m_tracks.size()) - 1);
    changed();
    return int(m_tracks.size()) - 1;
}

// Wzór → pętla audio zapisana w audio/ (nazwa z „_”, nowa przy każdej zmianie — cofanie wraca do poprzedniego pliku)
// ——— Tonacja (autotune) ———

void Studio::setKeyRoot(int r)
{
    r = ((r % 12) + 12) % 12;
    if (r == m_keyRoot)
        return;
    m_keyRoot = r;
    emit settingsChanged();
    changed();
}

void Studio::setKeyMinor(bool m)
{
    if (m == m_keyMinor)
        return;
    m_keyMinor = m;
    emit settingsChanged();
    changed();
}

QString Studio::keyName() const
{
    static const char *names[12] = {"C", "Cis", "D", "Dis", "E", "F", "Fis", "G", "Gis", "A", "B", "H"};
    const QString n = QString::fromUtf8(names[m_keyRoot]);
    return m_keyMinor ? n.toLower() + QStringLiteral("-moll") : n + QStringLiteral("-dur");
}

// Akordy → Melodia: te same dźwięki jako nuty piano rolla (dalej edytowane ręcznie)
bool Studio::inKey(int midi) const
{
    static const int minor[7] = {0, 2, 3, 5, 7, 8, 10}, major[7] = {0, 2, 4, 5, 7, 9, 11};
    const int pc = ((midi - m_keyRoot) % 12 + 12) % 12;
    for (int d = 0; d < 7; ++d)
        if ((m_keyMinor ? minor[d] : major[d]) == pc)
            return true;
    return false;
}

void Studio::simulateMidi(int pitch, int velocity)
{
    emit midiNote(pitch, velocity, velocity > 0);
}

// ——— Udostępnianie ———

QString Studio::artist() const
{
    QString a = QSettings().value(QStringLiteral("share/artist")).toString();
    if (a.isEmpty()) {
        a = qEnvironmentVariable("USER");
        if (!a.isEmpty())
            a[0] = a[0].toUpper();
    }
    return a;
}

void Studio::setArtist(const QString &a)
{
    QSettings().setValue(QStringLiteral("share/artist"), a.trimmed());
    emit artistChanged();
}

QString Studio::shareFolder() const
{
    const QString dir = m_folder + QStringLiteral("/Udostępnione");
    QDir().mkpath(dir);
    return dir;
}

// Przybliżony kształt piosenki: w każdym kawałku osi czasu najgłośniejszy szczyt klipów (z pętlami)
std::vector<float> Studio::roughWave(int bins) const
{
    std::vector<float> wave(size_t(bins), 0.f);
    const long long end = frames(duration());
    if (end <= 0)
        return wave;
    for (const Track &t : m_tracks) {
        if (ins(t).mute)
            continue;
        const float g = float(dbToGain(ins(t).volume));
        for (const Clip &c : t.clips) {
            const SourcePtr src = m_sources.value(c.file);
            if (!src || src->peaks.empty())
                continue;
            for (int b = 0; b < bins; ++b) {
                const long long at = end * b / bins + end / bins / 2;
                if (at < c.start || at >= c.start + c.length)
                    continue;
                const long long t0 = at - c.start;
                const long long si = c.srcStart + (c.loop ? (t0 + c.offset) % c.srcLen : t0);
                const size_t pi = size_t(si / AudioSource::PeakStep) * 2;
                if (pi + 1 < src->peaks.size())
                    wave[size_t(b)] = std::max(wave[size_t(b)], std::max(-src->peaks[pi], src->peaks[pi + 1]) * g);
            }
        }
    }
    float peak = 0;
    for (float v : wave)
        peak = std::max(peak, v);
    if (peak > 0)
        for (float &v : wave)
            v /= peak;
    return wave;
}

QString Studio::coverPreview(const QString &title, const QString &artist)
{
    if (!isOpen())
        return {};
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    QDir().mkpath(dir);
    // Nowa nazwa przy każdej zmianie — QML nie trzyma starego obrazka z pamięci podręcznej
    QFile::remove(dir + QStringLiteral("/okladka-%1.png").arg(m_coverVersion));
    const QString path = dir + QStringLiteral("/okladka-%1.png").arg(++m_coverVersion);
    Share::cover(title, artist, roughWave(72)).scaled(480, 480, Qt::KeepAspectRatio, Qt::SmoothTransformation).save(path);
    return QUrl::fromLocalFile(path).toString();
}

void Studio::shareSong(const QString &rawTitle, const QString &rawArtist)
{
    if (!isOpen() || m_exporting)
        return;
    const QString title = rawTitle.trimmed().isEmpty() ? m_name : rawTitle.trimmed();
    const QString artistName = rawArtist.trimmed();
    setArtist(artistName);
    QString fileName = title;
    fileName.replace(QLatin1Char('/'), QLatin1Char('-'));
    const QString path = shareFolder() + QLatin1Char('/') + fileName + QStringLiteral(".mp3");
    m_sharing = true;
    emit sharingChanged();
    const std::vector<float> wave = roughWave(72);
    QPointer<Studio> self(this);
    startExport(QStringLiteral("mp3"), path, [self, title, artistName, wave](bool ok, const QString &p, const QString &err) {
        if (!self)
            return;
        self->m_sharing = false;
        emit self->sharingChanged();
        if (!ok) {
            emit self->shareFailed(err.isEmpty() ? QStringLiteral("Nie udało się przygotować piosenki.") : err);
            return;
        }
        const QImage img = Share::cover(title, artistName, wave);
        img.save(QFileInfo(p).absolutePath() + QLatin1Char('/') + QFileInfo(p).completeBaseName() + QStringLiteral(" — okładka.jpg"), "JPEG", 92);
        Share::tagMp3(p, title, artistName, img);
        emit self->shareReady(p, QStringLiteral("song"));
    });
}

void Studio::shareProject()
{
    if (!isOpen() || m_sharing)
        return;
    save();
    QStringList files{ProjectFile};
    for (const Track &t : m_tracks)
        for (const Clip &c : t.clips)
            if (!files.contains(QStringLiteral("audio/") + c.file))
                files << QStringLiteral("audio/") + c.file;
    const QString zip = shareFolder() + QLatin1Char('/') + m_name + QStringLiteral(" — projekt.zip");
    m_sharing = true;
    emit sharingChanged();
    const QString folder = m_folder;
    QPointer<Studio> self(this);
    QThreadPool::globalInstance()->start([self, folder, files, zip] {
        QString err;
        const bool ok = Share::packProject(folder, files, zip, &err);
        QMetaObject::invokeMethod(qApp, [self, ok, zip, err] {
            if (!self)
                return;
            self->m_sharing = false;
            emit self->sharingChanged();
            if (ok)
                emit self->shareReady(zip, QStringLiteral("project"));
            else
                emit self->shareFailed(QStringLiteral("Nie udało się spakować projektu: ") + err);
        });
    });
}

QVariantList Studio::phones() const
{
    return Share::phones();
}

bool Studio::sendToPhone(const QString &id, const QString &path)
{
    const bool ok = Share::sendToPhone(id, path);
    emit message(ok ? QStringLiteral("Wysłano na telefon — plik pojawi się w Pobranych") : QStringLiteral("Nie udało się wysłać na telefon"));
    return ok;
}

void Studio::sendEmail(const QString &path, const QString &subject)
{
    // Program pocztowy z załącznikiem (xdg-email zna Thunderbirda, Evolution i aplikacje webowe z mailto)
    if (!QProcess::startDetached(QStringLiteral("xdg-email"), {QStringLiteral("--subject"), subject, QStringLiteral("--attach"), path}))
        emit message(QStringLiteral("Nie znaleziono programu pocztowego — plik jest w folderze Udostępnione"));
}

void Studio::copyFile(const QString &path)
{
    // Wklejenie w Plikach, komunikatorze albo przeglądarce (lista adresów + format menedżerów plików)
    auto *mime = new QMimeData;
    const QUrl url = QUrl::fromLocalFile(path);
    mime->setUrls({url});
    mime->setData(QStringLiteral("x-special/gnome-copied-files"), "copy\n" + url.toEncoded());
    QGuiApplication::clipboard()->setMimeData(mime);
    emit message(QStringLiteral("Skopiowano „%1” — wklej w komunikatorze albo w Plikach").arg(QFileInfo(path).fileName()));
}
