// Rack kanałów, wzory i mikser: model DAW-a. Kanały grają nuty na żywo przez instrumenty, wzory układa playlista
// (klipy z `pattern`), a inserty miksera sumują wszystko i wysyłają dalej. Wszystko trafia do migawki silnika.
#include "beatsynth.h"
#include "studio.h"

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonObject>
#include <QPointer>
#include <QSet>
#include <QThreadPool>
#include <algorithm>
#include <cmath>

namespace {
constexpr int Colors = 8;
double dbGain(double db) { return db <= -60 ? 0.0 : std::pow(10.0, db / 20); }
}

// ——— Inserty ———

int Studio::insertIndex(int id) const
{
    for (int i = 0; i < m_inserts.size(); ++i)
        if (m_inserts[i].id == id)
            return i;
    return -1;
}

int Studio::newInsert(const QString &name, int color)
{
    Insert in;
    in.id = m_nextId++;
    in.name = name;
    in.color = color;
    m_inserts.append(in);
    return in.id;
}

int Studio::addInsert(const QString &name)
{
    if (!isOpen() || m_inserts.size() >= Renderer::MaxTracks)
        return 0;
    checkpoint();
    const int id = newInsert(name.isEmpty() ? QStringLiteral("Insert %1").arg(m_inserts.size() + 1) : name, int(m_inserts.size()) % Colors);
    changed(false);
    return id;
}

void Studio::removeInsert(int id)
{
    const int at = insertIndex(id);
    if (at < 0)
        return;
    const bool used = std::any_of(m_tracks.begin(), m_tracks.end(), [id](const Track &t) { return t.insert == id; })
                      || std::any_of(m_channels.begin(), m_channels.end(), [id](const Channel &c) { return c.insert == id; });
    if (used) {
        emit message(QStringLiteral("Na ten insert gra jeszcze ścieżka albo kanał."));
        return;
    }
    for (Insert &in : m_inserts)
        in.sends.removeIf([id](const Send &s) { return s.to == id; });
    m_inserts.removeAt(at);
    changed(false);
}

// Czy z `from` da się dojść wysyłkami do `to`
static bool reaches(const QHash<int, QList<int>> &graph, int from, int to, QSet<int> &seen)
{
    if (from == to)
        return true;
    if (seen.contains(from))
        return false;
    seen.insert(from);
    for (int n : graph.value(from))
        if (reaches(graph, n, to, seen))
            return true;
    return false;
}

bool Studio::setInsertSend(int id, int to, double db)
{
    const int at = insertIndex(id);
    if (at < 0 || insertIndex(to) < 0 || id == to)
        return false;
    if (db > -60 && wouldLoop(id, to)) {
        emit message(QStringLiteral("Ta wysyłka zamknęłaby pętlę — dźwięk krążyłby w kółko."));
        return false;
    }
    checkpoint();
    QList<Send> &sends = m_inserts[at].sends;
    sends.removeIf([to](const Send &s) { return s.to == to; });
    if (db > -60)
        sends.append({to, std::min(db, 6.0)});
    changed(false);
    return true;
}

bool Studio::setInsertDuck(int id, int from, double amount)
{
    Insert *in = findInsert(id);
    if (!in || (from && (insertIndex(from) < 0 || wouldLoop(from, id)))) {
        if (in)
            emit message(QStringLiteral("Ten sidechain zamknąłby pętlę."));
        return false;
    }
    checkpoint();
    in = findInsert(id);
    in->duckFrom = from;
    in->duck = std::clamp(amount, 0.0, 1.0);
    changed(false);
    return true;
}

void Studio::freezeInsert(int id, bool on)
{
    Insert *in = findInsert(id);
    if (!in || !isOpen() || recording())
        return;
    if (!on) {
        checkpoint();
        findInsert(id)->frozen.clear();
        changed(false);
        return;
    }
    for (const Insert &o : std::as_const(m_inserts))
        for (const Send &s : o.sends)
            if (s.to == id) {
                emit message(QStringLiteral("Tego insertu nie da się zamrozić: dostaje dźwięk z wysyłki."));
                return;
            }
    const long long end = frames(duration());
    if (end <= 0)
        return;
    const QString path = uniqueAudioPath(QStringLiteral("_zamrożone %1").arg(in->name), QStringLiteral("wav"));
    const int at = insertIndex(id);
    std::shared_ptr<Snapshot> snap(buildSnapshot(true));
    // Tylko ten insert: nic innego nie musi grać, a automatyka i wejścia boczne zostają
    int own = 0;
    for (const PluginRT &p : snap->inserts[size_t(at)].fx)
        own += p.plugin->latency();
    snap->latency = 0;
    for (InsertRT &rt : snap->inserts) {
        rt.delay = 0;
        for (SendRT &sd : rt.sends)
            sd.delay = 0;
    }
    ++m_loading;
    emit busyChanged();
    const QString file = QFileInfo(path).fileName();
    const QString dir = m_folder;
    QPointer<Studio> self(this);
    const long long total = end + 3 * Engine::Rate;            // ogony efektów
    QThreadPool::globalInstance()->start([self, snap, at, total, own, path, file, id, dir] {
        const bool ok = Engine::renderInsert(*snap, at, total, own, path);
        QString err;
        std::shared_ptr<AudioSource> src = ok ? loadAudio(path, Engine::Rate, &err) : nullptr;
        QMetaObject::invokeMethod(qApp, [self, ok, src, file, id, dir] {
            if (!self)
                return;
            --self->m_loading;
            emit self->busyChanged();
            if (self->m_folder != dir)
                return;
            Insert *strip = self->findInsert(id);
            if (!ok || !src || !strip) {
                emit self->message(QStringLiteral("Nie udało się zamrozić insertu."));
                return;
            }
            self->checkpoint();
            src->file = file;
            self->m_sources.insert(file, src);
            self->findInsert(id)->frozen = file;
            self->changed(false);
            emit self->message(QStringLiteral("Zamrożone — wtyczki i instrumenty odpoczywają. Odmroź, żeby coś zmienić."));
        });
    });
}

bool Studio::setPluginSide(int insert, int slot, int from)
{
    Insert *in = findInsert(insert);
    if (!in || (from && (insertIndex(from) < 0 || wouldLoop(from, insert))))
        return false;
    checkpoint();
    for (Slot &s : findInsert(insert)->slots_)
        if (s.id == slot)
            s.side = from;
    changed(false);
    return true;
}

void Studio::setInsertToMaster(int id, bool on)
{
    const int at = insertIndex(id);
    if (at < 0)
        return;
    checkpoint();
    m_inserts[at].toMaster = on;
    changed(false);
}

// Źródła wysyłek i sidechainów przed celami
QList<int> Studio::insertOrder() const
{
    const int n = int(m_inserts.size());
    QList<int> pending(n, 0), out;
    QList<QList<int>> next(n);
    auto edge = [&](int from, int to) {
        if (from >= 0 && to >= 0) {
            next[from] << to;
            ++pending[to];
        }
    };
    for (int i = 0; i < n; ++i) {
        const Insert &in = m_inserts[i];
        for (const Send &s : in.sends)
            edge(i, insertIndex(s.to));
        if (in.duckFrom)
            edge(insertIndex(in.duckFrom), i);
        for (const Slot &s : in.slots_)
            if (s.side)
                edge(insertIndex(s.side), i);
    }
    QList<int> ready;
    for (int i = 0; i < n; ++i)
        if (!pending[i])
            ready << i;
    while (!ready.isEmpty()) {
        const int i = ready.takeFirst();
        out << i;
        for (int t : std::as_const(next[i]))
            if (--pending[t] == 0)
                ready << t;
    }
    return out;
}

// Czy połączenie source → target zamknęłoby pętlę: target już dochodzi do source
bool Studio::wouldLoop(int source, int target) const
{
    QHash<int, QList<int>> graph;
    for (const Insert &in : m_inserts) {
        for (const Send &s : in.sends)
            graph[in.id] << s.to;
        if (in.duckFrom)
            graph[in.duckFrom] << in.id;
        for (const Slot &s : in.slots_)
            if (s.side)
                graph[s.side] << in.id;
    }
    QSet<int> seen;
    return source == target || reaches(graph, target, source, seen);
}

// Kompensacja opóźnień: wtyczka spóźnia dźwięk, więc wszystko, co spotyka się z nią później, czeka tyle samo
void Studio::compileLatency(Snapshot *s)
{
    const int n = int(m_inserts.size());
    QList<int> own(n, 0), in(n, 0), out(n, 0);
    for (int i = 0; i < n; ++i)
        for (const PluginRT &p : s->inserts[size_t(i)].fx)
            own[i] += p.plugin->latency();
    // Wejście insertu: najpóźniejsze ze źródeł
    for (int i : s->order) {
        out[i] = in[i] + own[i];
        for (const SendRT &sd : s->inserts[size_t(i)].sends)
            if (sd.to >= 0 && sd.to < n)
                in[sd.to] = std::max(in[sd.to], out[i]);
    }
    int total = 0;
    for (int i = 0; i < n; ++i)
        if (s->inserts[size_t(i)].toMaster)
            total = std::max(total, out[i]);
    for (int i = 0; i < n; ++i) {
        InsertRT &rt = s->inserts[size_t(i)];
        rt.delay = rt.toMaster ? total - out[i] : 0;
        for (SendRT &sd : rt.sends)
            if (sd.to >= 0 && sd.to < n)
                sd.delay = in[sd.to] - out[i];
    }
    s->latency = total;
    m_engine.setPluginLatency(total);
}

QVariantList Studio::inserts() const
{
    QVariantList l;
    for (const Insert &in : m_inserts) {
        QVariantList sends, plugs;
        for (const Send &s : in.sends)
            sends.append(QVariantMap{{QStringLiteral("to"), s.to}, {QStringLiteral("db"), s.db}});
        for (const Slot &s : in.slots_)
            plugs.append(QVariantMap{{QStringLiteral("id"), s.id}, {QStringLiteral("name"), s.info.name}, {QStringLiteral("bypass"), s.bypass}, {QStringLiteral("missing"), !s.plugin},
                                     {QStringLiteral("side"), s.side}, {QStringLiteral("hasSide"), s.plugin && s.plugin->hasSidechain()}, {QStringLiteral("latency"), s.plugin ? s.plugin->latency() : 0}});
        l.append(QVariantMap{{QStringLiteral("id"), in.id}, {QStringLiteral("name"), in.name}, {QStringLiteral("color"), in.color},
                             {QStringLiteral("volume"), in.volume}, {QStringLiteral("pan"), in.pan}, {QStringLiteral("mute"), in.mute},
                             {QStringLiteral("solo"), in.solo}, {QStringLiteral("toMaster"), in.toMaster},
                             {QStringLiteral("duckFrom"), in.duckFrom}, {QStringLiteral("duck"), in.duck},
                             {QStringLiteral("frozen"), !in.frozen.isEmpty()},
                             {QStringLiteral("sends"), sends}, {QStringLiteral("plugins"), plugs},
                             {QStringLiteral("eqLow"), in.eqLow}, {QStringLiteral("eqMid"), in.eqMid}, {QStringLiteral("eqHigh"), in.eqHigh},
                             {QStringLiteral("comp"), in.comp}, {QStringLiteral("reverb"), in.reverb}, {QStringLiteral("lowCut"), in.lowCut},
                             {QStringLiteral("echo"), in.echo}, {QStringLiteral("drive"), in.drive}, {QStringLiteral("tune"), in.tune},
                             {QStringLiteral("double"), in.dbl}, {QStringLiteral("deess"), in.deess}, {QStringLiteral("denoise"), in.denoise},
                             {QStringLiteral("preset"), in.preset},
                             {QStringLiteral("hidden"), std::any_of(m_tracks.begin(), m_tracks.end(), [&in](const Track &t) { return t.insert == in.id && t.role == QLatin1String("auto"); })},
                             {QStringLiteral("track"), [&] {
                                  for (int i = 0; i < m_tracks.size(); ++i)
                                      if (m_tracks[i].insert == in.id)
                                          return i;
                                  return -1;
                              }()}});
    }
    return l;
}

QJsonObject Studio::insertJson(const Insert &t, bool pluginStates) const
{
    QJsonArray plugs, sends;
    for (const Slot &s : t.slots_) {
        QJsonObject o{{QStringLiteral("id"), s.id}, {QStringLiteral("path"), s.info.path}, {QStringLiteral("uid"), s.info.uid},
                      {QStringLiteral("name"), s.info.name}, {QStringLiteral("vendor"), s.info.vendor}, {QStringLiteral("bypass"), s.bypass},
                      {QStringLiteral("side"), s.side}};
        if (pluginStates)
            o.insert(QStringLiteral("state"), QString::fromLatin1((s.plugin ? s.plugin->state() : s.state).toBase64()));
        plugs.append(o);
    }
    for (const Send &s : t.sends)
        sends.append(QJsonObject{{QStringLiteral("to"), s.to}, {QStringLiteral("db"), s.db}});
    return QJsonObject{{QStringLiteral("id"), t.id}, {QStringLiteral("name"), t.name}, {QStringLiteral("color"), t.color},
                       {QStringLiteral("volume"), t.volume}, {QStringLiteral("pan"), t.pan}, {QStringLiteral("mute"), t.mute},
                       {QStringLiteral("solo"), t.solo}, {QStringLiteral("toMaster"), t.toMaster}, {QStringLiteral("sends"), sends},
                       {QStringLiteral("duckFrom"), t.duckFrom}, {QStringLiteral("duck"), t.duck}, {QStringLiteral("frozen"), t.frozen},
                       {QStringLiteral("plugins"), plugs},
                       {QStringLiteral("effects"), QJsonObject{{QStringLiteral("preset"), t.preset}, {QStringLiteral("lowCut"), t.lowCut},
                                                               {QStringLiteral("eqLow"), t.eqLow}, {QStringLiteral("eqMid"), t.eqMid},
                                                               {QStringLiteral("eqHigh"), t.eqHigh}, {QStringLiteral("compression"), t.comp},
                                                               {QStringLiteral("reverb"), t.reverb}, {QStringLiteral("echo"), t.echo},
                                                               {QStringLiteral("drive"), t.drive}, {QStringLiteral("autotune"), t.tune},
                                                               {QStringLiteral("double"), t.dbl}, {QStringLiteral("deess"), t.deess},
                                                               {QStringLiteral("denoise"), t.denoise}}}};
}

static Vst3::Info infoFrom(const QJsonObject &o)
{
    Vst3::Info i;
    i.path = o.value(QStringLiteral("path")).toString();
    i.uid = o.value(QStringLiteral("uid")).toString();
    i.name = o.value(QStringLiteral("name")).toString();
    i.vendor = o.value(QStringLiteral("vendor")).toString();
    return i;
}

// Te same klucze czyta stary format (pola wprost w ścieżce), więc starsze projekty przechodzą przez tę funkcję
Studio::Insert Studio::insertFromJson(const QJsonObject &o, const QHash<int, Slot> &oldSlots)
{
    Insert t;
    t.id = o.value(QStringLiteral("id")).toInt();
    t.name = o.value(QStringLiteral("name")).toString();
    t.color = o.value(QStringLiteral("color")).toInt() % Colors;
    t.volume = o.value(QStringLiteral("volume")).toDouble();
    t.pan = o.value(QStringLiteral("pan")).toDouble();
    t.mute = o.value(QStringLiteral("mute")).toBool();
    t.solo = o.value(QStringLiteral("solo")).toBool();
    t.toMaster = o.value(QStringLiteral("toMaster")).toBool(true);
    t.duckFrom = o.value(QStringLiteral("duckFrom")).toInt();
    t.duck = o.value(QStringLiteral("duck")).toDouble(0.6);
    t.frozen = o.value(QStringLiteral("frozen")).toString();
    if (!t.frozen.isEmpty() && !m_sources.contains(t.frozen))
        loadSources({t.frozen});
    for (const QJsonValue &v : o.value(QStringLiteral("sends")).toArray())
        t.sends.append({v.toObject().value(QStringLiteral("to")).toInt(), v.toObject().value(QStringLiteral("db")).toDouble()});
    const QJsonObject fx = o.value(QStringLiteral("effects")).toObject();
    auto unit = [&fx](const char *k) { return std::clamp(fx.value(QLatin1String(k)).toDouble(), 0.0, 1.0); };
    t.preset = fx.value(QStringLiteral("preset")).toString();
    t.lowCut = fx.value(QStringLiteral("lowCut")).toBool();
    t.eqLow = std::clamp(fx.value(QStringLiteral("eqLow")).toDouble(), -12.0, 12.0);
    t.eqMid = std::clamp(fx.value(QStringLiteral("eqMid")).toDouble(), -12.0, 12.0);
    t.eqHigh = std::clamp(fx.value(QStringLiteral("eqHigh")).toDouble(), -12.0, 12.0);
    t.comp = unit("compression");
    t.reverb = unit("reverb");
    t.echo = unit("echo");
    t.drive = unit("drive");
    t.tune = unit("autotune");
    t.dbl = unit("double");
    t.deess = unit("deess");
    t.denoise = std::clamp(fx.value(QStringLiteral("denoise")).toInt(), 0, 3);
    for (const QJsonValue &sv : o.value(QStringLiteral("plugins")).toArray()) {
        const QJsonObject so = sv.toObject();
        Slot s;
        s.id = so.value(QStringLiteral("id")).toInt();
        s.info = infoFrom(so);
        s.bypass = so.value(QStringLiteral("bypass")).toBool();
        s.side = so.value(QStringLiteral("side")).toInt();
        const bool hasState = so.contains(QStringLiteral("state"));
        if (hasState)
            s.state = QByteArray::fromBase64(so.value(QStringLiteral("state")).toString().toLatin1());
        else if (m_slotMemo.contains(s.id))
            s.state = m_slotMemo.value(s.id);
        if (const auto it = oldSlots.constFind(s.id); it != oldSlots.constEnd() && it->plugin && !hasState) {
            s.plugin = it->plugin;
        } else {
            s.plugin = makePlugin(s, true);
            if (!s.plugin)
                emit message(QStringLiteral("Nie ma wtyczki „%1” — gramy bez niej, jej ustawienia zostają w projekcie.").arg(s.info.name));
        }
        m_nextId = std::max(m_nextId, s.id + 1);
        t.slots_.append(s);
    }
    return t;
}

// ——— Kanały ———

Studio::Channel *Studio::findChannel(int id)
{
    for (Channel &c : m_channels)
        if (c.id == id)
            return &c;
    return nullptr;
}

std::shared_ptr<Instrument> Studio::makeInstrument(Channel &c)
{
    if (c.kind == QLatin1String("drum"))
        return std::make_shared<SamplerInstrument>(BeatSynth::kitSample(c.kit, c.row, Engine::Rate), c.root, true, Engine::Rate);
    if (c.kind == QLatin1String("sampler")) {
        const SourcePtr src = m_sources.value(c.file);
        return src ? std::make_shared<SamplerInstrument>(src, c.root, c.oneShot, Engine::Rate) : nullptr;
    }
    if (c.kind == QLatin1String("synth"))
        return std::make_shared<SynthInstrument>(BeatSynth::instrumentOf(c.inst), Engine::Rate);
    if (c.kind == QLatin1String("bass")) {
        const BeatSynth::BassParams p = BeatSynth::bassParams(c.kit);
        return std::make_shared<Bass808>(Bass808::Params{p.decay, p.glide, p.drive}, Engine::Rate);
    }
    if (c.kind == QLatin1String("vst")) {
        if (!c.vst.plugin)
            c.vst.plugin = makePlugin(c.vst, true);
        return c.vst.plugin ? std::make_shared<VstInstrument>(c.vst.plugin) : nullptr;
    }
    return nullptr;
}

int Studio::addChannel(const QString &kind, const QString &arg, const QString &name)
{
    if (!isOpen() || m_channels.size() >= Renderer::MaxChannels)
        return 0;
    Channel c;
    c.kind = kind;
    c.color = int(m_channels.size()) % Colors;
    if (kind == QLatin1String("drum")) {
        c.kit = arg.section(QLatin1Char(':'), 0, 0);
        c.row = arg.section(QLatin1Char(':'), 1, 1);
        c.name = c.row;
    } else if (kind == QLatin1String("sampler")) {
        c.file = arg;
        c.name = arg.section(QLatin1Char('.'), 0, 0);
        c.oneShot = true;
        if (!m_sources.contains(arg))
            loadSources({arg});
    } else if (kind == QLatin1String("synth")) {
        c.inst = arg;
        c.name = arg;
    } else if (kind == QLatin1String("bass")) {
        c.kit = arg;
        c.name = QStringLiteral("808");
        c.root = 36;
    } else if (kind == QLatin1String("vst")) {
        for (const Vst3::Info &i : std::as_const(m_pluginList))
            if (i.uid == arg)
                c.vst.info = i;
        if (c.vst.info.uid.isEmpty() || !c.vst.info.instrument) {
            emit message(QStringLiteral("To nie jest instrument VST3."));
            return 0;
        }
        c.name = c.vst.info.name;
    } else {
        return 0;
    }
    if (!name.isEmpty())
        c.name = name;
    checkpoint();
    c.id = m_nextId++;
    c.vst.id = c.id;
    c.instrument = makeInstrument(c);
    if (kind == QLatin1String("vst") && !c.instrument) {
        emit message(QStringLiteral("Wtyczka „%1” nie chce się uruchomić.").arg(c.name));
        return 0;
    }
    c.insert = newInsert(c.name, c.color);      // każdy kanał ma od razu własny pas w mikserze
    m_channels.append(c);
    changed(false);
    if (kind == QLatin1String("vst"))
        c.vst.plugin->openEditor();
    return c.id;
}

void Studio::removeChannel(int id)
{
    for (int i = 0; i < m_channels.size(); ++i) {
        if (m_channels[i].id != id)
            continue;
        checkpoint();
        if (m_channels[i].vst.plugin) {
            m_channels[i].vst.plugin->closeEditor();
            m_slotMemo.insert(id, m_channels[i].vst.plugin->state());
        }
        const int insert = m_channels[i].insert;
        m_channels.removeAt(i);
        for (Pattern &p : m_patterns)
            p.data.remove(id);
        const bool used = std::any_of(m_tracks.begin(), m_tracks.end(), [insert](const Track &t) { return t.insert == insert; })
                          || std::any_of(m_channels.begin(), m_channels.end(), [insert](const Channel &c) { return c.insert == insert; });
        if (!used)
            removeInsert(insert);
        changed(false);
        return;
    }
}

void Studio::setChannelInsert(int id, int insert)
{
    Channel *c = findChannel(id);
    if (!c || insertIndex(insert) < 0)
        return;
    checkpoint();
    c->insert = insert;
    changed(false);
}

void Studio::setChannelVolume(int id, double db)
{
    if (Channel *c = findChannel(id)) {
        c->volume = std::clamp(db, -60.0, 6.0);
        changed(false);
    }
}

void Studio::setChannelPan(int id, double pan)
{
    if (Channel *c = findChannel(id)) {
        c->pan = std::clamp(pan, -1.0, 1.0);
        changed(false);
    }
}

void Studio::setChannelMute(int id, bool on)
{
    if (Channel *c = findChannel(id)) {
        c->mute = on;
        changed(false);
    }
}

void Studio::openChannelPlugin(int id)
{
    Channel *c = findChannel(id);
    if (c && c->vst.plugin && !c->vst.plugin->openEditor())
        emit message(QStringLiteral("Okno wtyczki „%1” się nie otworzyło (wymaga XWayland).").arg(c->name));
}

QVariantList Studio::channels() const
{
    QVariantList l;
    for (const Channel &c : m_channels)
        l.append(QVariantMap{{QStringLiteral("id"), c.id}, {QStringLiteral("name"), c.name}, {QStringLiteral("color"), c.color},
                             {QStringLiteral("kind"), c.kind}, {QStringLiteral("insert"), c.insert}, {QStringLiteral("volume"), c.volume},
                             {QStringLiteral("pan"), c.pan}, {QStringLiteral("mute"), c.mute},
                             {QStringLiteral("missing"), !c.instrument}});
    return l;
}

// ——— Wzory ———

Studio::Pattern *Studio::findPattern(int id)
{
    for (Pattern &p : m_patterns)
        if (p.id == id)
            return &p;
    return nullptr;
}

long long Studio::patternFrames(const Pattern &p) const
{
    return llround(p.bars * m_beatsPerBar * 60.0 / m_bpm * Engine::Rate);
}

int Studio::addPattern(const QString &name, int bars)
{
    if (!isOpen())
        return 0;
    checkpoint();
    Pattern p;
    p.id = m_nextId++;
    p.name = name.isEmpty() ? QStringLiteral("Wzór %1").arg(m_patterns.size() + 1) : name;
    p.bars = std::clamp(bars, 1, 32);
    m_patterns.append(p);
    m_curPattern = p.id;
    changed(false);
    return p.id;
}

void Studio::removePattern(int id)
{
    for (int i = 0; i < m_patterns.size(); ++i) {
        if (m_patterns[i].id != id)
            continue;
        checkpoint();
        m_patterns.removeAt(i);
        for (Track &t : m_tracks)
            t.clips.removeIf([id](const Clip &c) { return c.pattern == id; });
        if (m_curPattern == id)
            m_curPattern = m_patterns.isEmpty() ? 0 : m_patterns.first().id;
        applyPatternLoop();
        changed();
        return;
    }
}

void Studio::setPatternBars(int id, int bars)
{
    if (Pattern *p = findPattern(id)) {
        checkpoint();
        p->bars = std::clamp(bars, 1, 32);
        for (Track &t : m_tracks)
            for (Clip &c : t.clips)
                if (c.pattern == id)
                    c.srcLen = patternFrames(*p);
        applyPatternLoop();
        changed();
    }
}

void Studio::setStep(int pattern, int channel, int step, double velocity)
{
    Pattern *p = findPattern(pattern);
    if (!p || !findChannel(channel) || step < 0 || step >= p->bars * m_beatsPerBar * 4)
        return;
    checkpoint();
    QList<double> &steps = p->data[channel].steps;
    while (steps.size() <= step)
        steps.append(0);
    steps[step] = std::clamp(velocity, 0.0, 1.0);
    changed(false);
}

void Studio::setPatternNotes(int pattern, int channel, const QVariantList &notes)
{
    Pattern *p = findPattern(pattern);
    if (!p || !findChannel(channel))
        return;
    checkpoint();
    QList<PatNote> out;
    for (const QVariant &v : notes) {
        const QVariantMap m = v.toMap();
        out.append({std::max(0.0, m.value(QStringLiteral("step")).toDouble()), std::max(0.0625, m.value(QStringLiteral("len"), 1.0).toDouble()),
                    std::clamp(m.value(QStringLiteral("pitch"), 60).toInt(), 0, 127), std::clamp(m.value(QStringLiteral("vel"), 0.8).toDouble(), 0.0, 1.0)});
    }
    p->data[channel].notes = out;
    changed(false);
}

QVariantMap Studio::patternData(int pattern, int channel) const
{
    QVariantList steps, notes;
    for (const Pattern &p : m_patterns) {
        if (p.id != pattern)
            continue;
        const PatData d = p.data.value(channel);
        for (double v : d.steps)
            steps << v;
        for (const PatNote &n : d.notes)
            notes.append(QVariantMap{{QStringLiteral("step"), n.step}, {QStringLiteral("len"), n.len}, {QStringLiteral("pitch"), n.pitch}, {QStringLiteral("vel"), n.vel}});
    }
    return {{QStringLiteral("steps"), steps}, {QStringLiteral("notes"), notes}};
}

int Studio::addPatternClip(int track, int pattern, double start, double length)
{
    const Pattern *p = findPattern(pattern);
    if (!p || track < 0 || track >= m_tracks.size() || m_tracks[track].kind != QLatin1String("audio"))
        return 0;
    checkpoint();
    Clip c;
    c.id = m_nextId++;
    c.name = p->name;
    c.pattern = pattern;
    c.loop = true;
    c.srcLen = patternFrames(*p);
    c.start = frames(std::max(0.0, start));
    c.length = length > 0 ? frames(length) : c.srcLen;
    carve(track, c.start, c.start + c.length, 0);
    m_tracks[track].clips.append(c);
    changed();
    return c.id;
}

QVariantList Studio::patterns() const
{
    QVariantList l;
    for (const Pattern &p : m_patterns)
        l.append(QVariantMap{{QStringLiteral("id"), p.id}, {QStringLiteral("name"), p.name}, {QStringLiteral("bars"), p.bars}});
    return l;
}

void Studio::setCurrentPattern(int id)
{
    if (id == m_curPattern || !findPattern(id))
        return;
    m_curPattern = id;
    applyPatternLoop();
    changed(false);
}

void Studio::setPatternMode(bool on)
{
    if (on == m_patMode || recording())
        return;
    m_patMode = on;
    if (on)
        seek(0);
    applyPatternLoop();
    changed(false);
}

void Studio::applyPatternLoop()
{
    const Pattern *p = m_patMode ? findPattern(m_curPattern) : nullptr;
    if (p)
        m_engine.setCycle(true, 0, patternFrames(*p));
    else
        m_engine.setCycle(m_cycle, frames(m_cycleStart), frames(m_cycleEnd));
}

void Studio::setSwing(double v)
{
    v = std::clamp(v, 0.0, 0.5);
    if (v == m_swing)
        return;
    m_swing = v;
    changed(false);
}

// Nuty kanałów na oś czasu: tryb WZÓR — bieżący wzór, UTWÓR — klipy wzorów z playlisty
void Studio::compileChannels(Snapshot *s, bool forExport)
{
    const double stepFrames = 60.0 / m_bpm / 4 * Engine::Rate;
    struct Place { const Pattern *p; long long start, end, phase; };
    QList<Place> places;
    if (m_patMode) {
        if (const Pattern *p = findPattern(m_curPattern))
            places.append({p, 0, patternFrames(*p), 0});
    } else {
        for (const Track &t : std::as_const(m_tracks))
            for (const Clip &c : t.clips)
                if (const Pattern *p = c.pattern ? findPattern(c.pattern) : nullptr)
                    places.append({p, c.start, c.start + c.length, c.offset});
    }
    for (Channel &c : m_channels) {
        ChannelRT rt;
        if (!c.instrument)
            c.instrument = makeInstrument(c);
        std::shared_ptr<Instrument> inst = c.instrument;
        if (forExport && inst) {
            Channel copy = c;
            if (c.vst.plugin) {
                copy.vst.state = c.vst.plugin->state();
                copy.vst.plugin.reset();
            }
            inst = makeInstrument(copy);
            if (copy.vst.plugin) {
                s->plugins.push_back(copy.vst.plugin);
                m_snapPlugins.insert(c.id, copy.vst.plugin.get());
            }
        } else if (c.vst.plugin) {
            m_snapPlugins.insert(c.id, c.vst.plugin.get());
        }
        if (inst) {
            s->instruments.push_back(inst);
            rt.inst = inst.get();
        }
        rt.insert = insertIndex(c.insert);
        const double g = dbGain(c.volume), pan = std::clamp(c.pan, -1.0, 1.0);
        rt.gainL = float(g * (pan > 0 ? 1 - pan : 1));
        rt.gainR = float(g * (pan < 0 ? 1 + pan : 1));
        rt.audible = !c.mute;
        if (const Insert *in = findInsert(c.insert); in && !in->frozen.isEmpty() && m_sources.contains(in->frozen)) {
            rt.inst = nullptr;                  // gra plik zamrożonego insertu
            s->channels.push_back(std::move(rt));
            continue;
        }
        for (const Place &pl : std::as_const(places)) {
            const auto it = pl.p->data.constFind(c.id);
            if (it == pl.p->data.constEnd())
                continue;
            const long long len = patternFrames(*pl.p);
            auto put = [&](double step, double steps, int pitch, double vel) {
                // Rozstaw co drugiej szesnastki — zawsze względem siatki kroków
                const double swung = step + (std::fmod(step, 2.0) >= 1.0 ? m_swing : 0.0);
                for (long long base = pl.start - pl.phase % len; base < pl.end; base += len) {
                    const long long at = base + llround(swung * stepFrames);
                    if (at < pl.start || at >= pl.end)
                        continue;
                    rt.events.push_back({at, pitch, float(vel), true});
                    rt.events.push_back({std::min(pl.end - 1, at + llround(steps * stepFrames)), pitch, 0.f, false});
                }
            };
            for (int i = 0; i < it->steps.size(); ++i)
                if (it->steps[i] > 0)
                    put(i, 1, c.root, it->steps[i]);
            for (const PatNote &n : it->notes)
                put(n.step, n.len, n.pitch, n.vel);
        }
        // Puszczenia przed uderzeniami w tej samej chwili
        std::stable_sort(rt.events.begin(), rt.events.end(), [](const SeqEvent &a, const SeqEvent &b) { return a.at != b.at ? a.at < b.at : !a.on && b.on; });
        s->channels.push_back(std::move(rt));
    }
}

// ——— Automatyka ———

QVariantList Studio::autoTargets(int insert) const
{
    QVariantList out;
    auto add = [&out](const QString &t, const QString &l) { out.append(QVariantMap{{QStringLiteral("target"), t}, {QStringLiteral("label"), l}}); };
    for (const Insert &in : m_inserts) {
        if (in.id != insert)
            continue;
        const QString id = QString::number(in.id);
        add(QStringLiteral("vol:") + id, in.name + QStringLiteral(" — głośność"));
        add(QStringLiteral("pan:") + id, in.name + QStringLiteral(" — panorama"));
        add(QStringLiteral("reverb:") + id, in.name + QStringLiteral(" — pogłos"));
        add(QStringLiteral("echo:") + id, in.name + QStringLiteral(" — echo"));
        add(QStringLiteral("drive:") + id, in.name + QStringLiteral(" — przester"));
        add(QStringLiteral("double:") + id, in.name + QStringLiteral(" — dubel"));
        for (const Slot &s : in.slots_)
            if (s.plugin)
                for (const Vst3::Param &p : s.plugin->params())
                    if (p.automatable)
                        add(QStringLiteral("plug:%1:%2").arg(s.id).arg(p.id), s.info.name + QStringLiteral(" — ") + p.name);
    }
    return out;
}

QVariantList Studio::channelAutoTargets(int channel) const
{
    QVariantList out;
    auto add = [&out](const QString &t, const QString &l) { out.append(QVariantMap{{QStringLiteral("target"), t}, {QStringLiteral("label"), l}}); };
    for (const Channel &c : m_channels) {
        if (c.id != channel)
            continue;
        add(QStringLiteral("chvol:%1").arg(c.id), c.name + QStringLiteral(" — głośność kanału"));
        if (c.vst.plugin)
            for (const Vst3::Param &p : c.vst.plugin->params())
                if (p.automatable)
                    add(QStringLiteral("chplug:%1:%2").arg(c.id).arg(p.id), c.name + QStringLiteral(" — ") + p.name);
    }
    return out;
}

int Studio::addAutomation(const QString &target, const QString &label)
{
    if (!isOpen() || target.isEmpty())
        return 0;
    // Własny pas, żeby krzywe nie mieszały się z nagraniami
    int lane = -1;
    for (int i = 0; i < m_tracks.size() && lane < 0; ++i)
        if (m_tracks[i].role == QLatin1String("auto"))
            lane = i;
    bool freeSpot = false;
    if (lane >= 0)
        freeSpot = !std::any_of(m_tracks[lane].clips.begin(), m_tracks[lane].clips.end(), [&](const Clip &c) { return c.autoTarget != target; });
    if (lane < 0 || !freeSpot) {
        addTrack(QStringLiteral("Automatyka"));
        lane = int(m_tracks.size()) - 1;
        m_tracks[lane].role = QStringLiteral("auto");
    } else {
        checkpoint();
    }
    const long long bar = llround(60.0 / m_bpm * m_beatsPerBar * Engine::Rate);
    Clip c;
    c.id = m_nextId++;
    c.name = label;
    c.autoTarget = target;
    c.length = c.srcLen = std::max(8 * bar, (frames(duration()) + bar - 1) / bar * bar);
    c.autoPts = {{0, 0.7}, {double(c.length), 0.7}};
    m_tracks[lane].clips.append(c);
    m_selClip = c.id;
    emit selectionChanged();
    changed();
    return c.id;
}

void Studio::setAutoPoints(int clip, const QVariantList &points)
{
    Clip *c = findClip(clip);
    if (!c || c->autoTarget.isEmpty())
        return;
    checkpoint();
    c = findClip(clip);
    QList<QPointF> pts;
    for (const QVariant &v : points) {
        const QVariantMap m = v.toMap();
        pts.append({std::clamp(m.value(QStringLiteral("t")).toDouble() * Engine::Rate, 0.0, double(c->length)),
                    std::clamp(m.value(QStringLiteral("v")).toDouble(), 0.0, 1.0)});
    }
    std::stable_sort(pts.begin(), pts.end(), [](const QPointF &a, const QPointF &b) { return a.x() < b.x(); });
    c->autoPts = pts;
    changed();
}

void Studio::compileAutos(Snapshot *s)
{
    static const QHash<QString, AutoRT::Kind> kinds{{QStringLiteral("vol"), AutoRT::Volume}, {QStringLiteral("pan"), AutoRT::Pan},
                                                    {QStringLiteral("reverb"), AutoRT::Reverb}, {QStringLiteral("echo"), AutoRT::Echo},
                                                    {QStringLiteral("drive"), AutoRT::Drive}, {QStringLiteral("double"), AutoRT::Double},
                                                    {QStringLiteral("deess"), AutoRT::Deess}};
    if (m_patMode) {
        m_snapPlugins.clear();
        return;
    }
    for (const Track &t : std::as_const(m_tracks)) {
        for (const Clip &c : t.clips) {
            if (c.autoTarget.isEmpty() || c.autoPts.isEmpty())
                continue;
            const QStringList p = c.autoTarget.split(QLatin1Char(':'));
            AutoRT a;
            if (p[0] == QLatin1String("master")) {
                a.kind = AutoRT::Master;
            } else if (p[0] == QLatin1String("plug") || p[0] == QLatin1String("chplug")) {
                a.kind = AutoRT::Param;
                a.plugin = m_snapPlugins.value(p.value(1).toInt());
                a.param = p.value(2).toUInt();
                if (!a.plugin)
                    continue;
            } else if (p[0] == QLatin1String("chvol")) {
                a.kind = AutoRT::ChannelVolume;
                a.index = -1;
                for (int i = 0; i < m_channels.size(); ++i)
                    if (m_channels[i].id == p.value(1).toInt())
                        a.index = i;
            } else if (kinds.contains(p[0])) {
                a.kind = kinds.value(p[0]);
                a.index = insertIndex(p.value(1).toInt());
            } else {
                continue;
            }
            a.start = c.start;
            a.end = c.start + c.length;
            for (const QPointF &q : c.autoPts)
                a.points.push_back({c.start + llround(q.x()), float(q.y())});
            s->autos.push_back(std::move(a));
        }
    }
    m_snapPlugins.clear();
}

// ——— Beat Maker → kanały ———

int Studio::rackChannel(const QString &kind, const QString &kit, const QString &row, const QString &inst, const QString &name, int insert, double volume)
{
    Channel c;
    c.id = m_nextId++;
    c.kind = kind;
    c.kit = kit;
    c.row = row;
    c.inst = inst;
    c.name = name;
    c.insert = insert;
    c.volume = volume;
    c.color = int(m_channels.size()) % Colors;
    c.root = kind == QLatin1String("bass") ? 36 : 60;
    c.instrument = makeInstrument(c);
    m_channels.append(c);
    if (!m_selChannel)
        m_selChannel = c.id;
    return c.id;
}

static const struct { const char *row, *name; } s_rows[] = {
    {"kick", "Stopa"}, {"snare", "Werbel"}, {"clap", "Klaśnięcie"}, {"hat", "Hi-hat"}, {"openhat", "Otwarty hat"}, {"perc", "Perkusjonalia"},
};

void Studio::defaultRack()
{
    const int insert = newInsert(QStringLiteral("Perkusja"), 0);
    for (const auto &r : s_rows)
        rackChannel(QStringLiteral("drum"), QStringLiteral("trap"), QString::fromLatin1(r.row), {}, QString::fromUtf8(r.name), insert, -2.5);
    Pattern p;
    p.id = m_nextId++;
    p.name = QStringLiteral("Wzór 1");
    p.bars = 1;
    m_patterns.append(p);
    m_curPattern = p.id;
    m_patMode = true;
    applyPatternLoop();
}

// Dawna ścieżka wzoru: to samo granie jako kanały na jej insercie i klipy wzoru na jej pasie
void Studio::convertPatternTrack(int index)
{
    Track &t = m_tracks[index];
    const QJsonObject old = t.pattern;
    const BeatSynth::Kind kind = t.kind == QLatin1String("bass") ? BeatSynth::Bass : t.kind == QLatin1String("keys") ? BeatSynth::Keys
                               : t.kind == QLatin1String("melody") ? BeatSynth::Melody : BeatSynth::Drums;
    const QString kit = old.value(QStringLiteral("kit")).toString(QStringLiteral("trap"));
    Pattern p;
    p.id = m_nextId++;
    p.name = t.name;
    if (kind == BeatSynth::Drums) {
        p.bars = std::clamp(old.value(QStringLiteral("bars")).toInt(2), 1, 32);
        m_swing = std::max(m_swing, std::clamp(old.value(QStringLiteral("swing")).toDouble(), 0.0, 0.5));
        const QJsonObject rows = old.value(QStringLiteral("rows")).toObject();
        const QJsonArray rolls = old.value(QStringLiteral("rolls")).toArray();
        const int steps = p.bars * 16;
        for (const auto &r : s_rows) {
            const QString row = QString::fromLatin1(r.row);
            const int id = rackChannel(QStringLiteral("drum"), kit, row, {}, QString::fromUtf8(r.name), t.insert, -2.5);
            PatData d;
            const QJsonArray cells = rows.value(row).toArray();
            for (int i = 0; i < steps; ++i) {
                const double v = cells.at(i).toDouble();
                const int roll = row == QLatin1String("hat") ? std::clamp(rolls.at(i).toInt(1), 1, 4) : 1;
                if (v > 0 && roll > 1) {
                    for (int k = 0; k < roll; ++k)
                        d.notes.append({i + double(k) / roll, 1.0 / roll, 60, v * (1 - 0.12 * k)});
                } else {
                    d.steps.append(v);
                    continue;
                }
                d.steps.append(0);
            }
            p.data.insert(id, d);
        }
    } else if (kind == BeatSynth::Bass) {
        p.bars = std::clamp(old.value(QStringLiteral("bars")).toInt(2), 1, 32);
        const int id = rackChannel(QStringLiteral("bass"), kit, {}, {}, t.name, t.insert, -3);
        const QJsonArray notes = old.value(QStringLiteral("notes")).toArray();
        PatData d;
        const int steps = p.bars * 16;
        for (int i = 0; i < steps; ++i) {
            const int degree = notes.at(i).toInt(-1);
            if (degree < 0)
                continue;
            int len = 1;
            while (i + len < steps && notes.at(i + len).toInt(-1) < 0)
                ++len;
            d.notes.append({double(i), double(len), BeatSynth::noteMidi(old, std::min(degree, 14)), 1.0});
        }
        p.data.insert(id, d);
    } else {
        QJsonObject withKey = old;
        withKey.insert(QStringLiteral("keyRoot"), m_keyRoot);
        withKey.insert(QStringLiteral("keyMinor"), m_keyMinor);
        const QJsonArray notes = kind == BeatSynth::Keys ? BeatSynth::chordNotes(withKey) : old.value(QStringLiteral("notes")).toArray();
        p.bars = kind == BeatSynth::Keys ? std::clamp(int(old.value(QStringLiteral("chords")).toArray().size()), 1, 32)
                                         : std::clamp(old.value(QStringLiteral("bars")).toInt(4), 1, 32);
        const int id = rackChannel(QStringLiteral("synth"), {}, {}, old.value(QStringLiteral("instrument")).toString(QStringLiteral("piano")), t.name, t.insert, 0);
        PatData d;
        for (const QJsonValue &v : notes) {
            const QJsonObject n = v.toObject();
            d.notes.append({n.value(QStringLiteral("step")).toDouble(), std::max(1.0, n.value(QStringLiteral("len")).toDouble(2)),
                            n.value(QStringLiteral("pitch")).toInt(60), n.value(QStringLiteral("vel")).toDouble(0.85)});
        }
        p.data.insert(id, d);
    }
    m_patterns.append(p);
    if (!m_curPattern)
        m_curPattern = p.id;
    const long long loop = patternFrames(p);
    for (Clip &c : t.clips) {
        c.file.clear();
        c.name = p.name;
        c.pattern = p.id;
        c.loop = true;
        c.srcStart = 0;
        c.srcLen = loop;
        c.offset = ((c.offset % loop) + loop) % loop;
    }
    if (t.clips.isEmpty()) {
        const long long bar = llround(60.0 / m_bpm * m_beatsPerBar * Engine::Rate);
        Clip c;
        c.id = m_nextId++;
        c.name = p.name;
        c.pattern = p.id;
        c.loop = true;
        c.srcLen = loop;
        c.length = std::max(8 * bar, (frames(duration()) + bar - 1) / bar * bar);
        t.clips.append(c);
    }
    t.kind = QStringLiteral("audio");
    t.pattern = {};
}

// ——— Mikser: drobiazgi i zaznaczenie ———

Studio::Insert *Studio::findInsert(int id)
{
    const int at = insertIndex(id);
    return at < 0 ? nullptr : &m_inserts[at];
}

void Studio::setInsertVolume(int id, double db)
{
    if (Insert *in = findInsert(id)) {
        in->volume = std::clamp(db, -60.0, 6.0);
        changed(false);
    }
}

void Studio::setInsertPan(int id, double pan)
{
    if (Insert *in = findInsert(id)) {
        in->pan = std::clamp(pan, -1.0, 1.0);
        changed(false);
    }
}

void Studio::setInsertMute(int id, bool on)
{
    if (Insert *in = findInsert(id)) {
        in->mute = on;
        changed(false);
    }
}

void Studio::setInsertSolo(int id, bool on)
{
    if (Insert *in = findInsert(id)) {
        in->solo = on;
        changed(false);
    }
}

void Studio::applyInsertPreset(int id, const QString &preset)
{
    if (!findInsert(id))
        return;
    checkpoint();
    applyPresetTo(*findInsert(id), preset);
    changed(false);
}

void Studio::renameInsert(int id, const QString &name)
{
    if (Insert *in = findInsert(id); in && !name.trimmed().isEmpty()) {
        in->name = name.trimmed();
        changed(false);
    }
}

void Studio::renameChannel(int id, const QString &name)
{
    if (Channel *c = findChannel(id); c && !name.trimmed().isEmpty()) {
        c->name = name.trimmed();
        changed(false);
    }
}

void Studio::renamePattern(int id, const QString &name)
{
    if (Pattern *p = findPattern(id); p && !name.trimmed().isEmpty()) {
        p->name = name.trimmed();
        for (Track &t : m_tracks)
            for (Clip &c : t.clips)
                if (c.pattern == id)
                    c.name = p->name;
        changed();
    }
}

int Studio::duplicatePattern(int id)
{
    const Pattern *p = findPattern(id);
    if (!p)
        return 0;
    checkpoint();
    Pattern copy = *findPattern(id);
    copy.id = m_nextId++;
    copy.name = QStringLiteral("Wzór %1").arg(m_patterns.size() + 1);
    m_patterns.append(copy);
    m_curPattern = copy.id;
    applyPatternLoop();
    changed(false);
    return copy.id;
}

void Studio::setSelectedChannel(int id)
{
    const Channel *c = findChannel(id);
    if (!c || id == m_selChannel)
        return;
    m_selChannel = id;
    m_selInsert = c->insert;
    emit selectionChanged();
}

void Studio::setSelectedInsert(int id)
{
    if (id == m_selInsert || !findInsert(id))
        return;
    m_selInsert = id;
    emit selectionChanged();
}

void Studio::channelNoteOn(int id, int pitch, double velocity)
{
    for (int i = 0; i < m_channels.size(); ++i)
        if (m_channels[i].id == id)
            m_engine.channelNote(i, true, std::clamp(pitch, 0, 127), float(std::clamp(velocity, 0.0, 1.0)));
}

void Studio::channelNoteOff(int id, int pitch)
{
    for (int i = 0; i < m_channels.size(); ++i)
        if (m_channels[i].id == id)
            m_engine.channelNote(i, false, std::clamp(pitch, 0, 127), 0.f);
}

QVariantList Studio::patternPreview(int id) const
{
    QVariantList out;
    for (const Pattern &p : m_patterns) {
        if (p.id != id)
            continue;
        const double steps = p.bars * m_beatsPerBar * 4;
        // Wiersz każdego kanału z krokami, a nuty — według wysokości
        int row = 0, rows = 0;
        for (const Channel &c : m_channels)
            rows += p.data.contains(c.id) && !p.data.value(c.id).steps.isEmpty();
        for (const Channel &c : m_channels) {
            const auto it = p.data.constFind(c.id);
            if (it == p.data.constEnd())
                continue;
            bool used = false;
            for (int i = 0; i < it->steps.size(); ++i)
                if (it->steps[i] > 0) {
                    used = true;
                    out.append(QVariantMap{{QStringLiteral("x"), i / steps}, {QStringLiteral("w"), 0.8 / steps}, {QStringLiteral("y"), rows > 1 ? double(row) / (rows - 1) : 0.5}});
                }
            row += !it->steps.isEmpty();
            Q_UNUSED(used);
            for (const PatNote &n : it->notes)
                out.append(QVariantMap{{QStringLiteral("x"), n.step / steps}, {QStringLiteral("w"), n.len / steps}, {QStringLiteral("y"), 1.0 - std::clamp((n.pitch - 24) / 72.0, 0.0, 1.0)}});
        }
    }
    return out;
}

QStringList Studio::projectSounds() const
{
    QStringList out;
    if (m_folder.isEmpty())
        return out;
    for (const QFileInfo &fi : QDir(m_folder + QStringLiteral("/audio")).entryInfoList(QDir::Files, QDir::Name))
        if (!fi.fileName().startsWith(QLatin1Char('_')))
            out << fi.fileName();
    return out;
}

// ——— Zapis ———

void Studio::clearRack()
{
    m_inserts.clear();
    m_channels.clear();
    m_patterns.clear();
    m_curPattern = 0;
    m_swing = 0;
    m_patMode = false;
    m_selChannel = m_selInsert = 0;
}

QJsonObject Studio::rackJson(bool pluginStates) const
{
    QJsonArray inserts, channels, patterns;
    for (const Insert &in : m_inserts)
        inserts.append(insertJson(in, pluginStates));
    for (const Channel &c : m_channels) {
        QJsonObject o{{QStringLiteral("id"), c.id}, {QStringLiteral("name"), c.name}, {QStringLiteral("color"), c.color},
                      {QStringLiteral("insert"), c.insert}, {QStringLiteral("volume"), c.volume}, {QStringLiteral("pan"), c.pan},
                      {QStringLiteral("mute"), c.mute}, {QStringLiteral("kind"), c.kind}, {QStringLiteral("kit"), c.kit},
                      {QStringLiteral("row"), c.row}, {QStringLiteral("file"), c.file}, {QStringLiteral("inst"), c.inst},
                      {QStringLiteral("root"), c.root}, {QStringLiteral("oneShot"), c.oneShot}};
        if (c.kind == QLatin1String("vst")) {
            QJsonObject v{{QStringLiteral("path"), c.vst.info.path}, {QStringLiteral("uid"), c.vst.info.uid},
                          {QStringLiteral("name"), c.vst.info.name}, {QStringLiteral("vendor"), c.vst.info.vendor}};
            if (pluginStates)
                v.insert(QStringLiteral("state"), QString::fromLatin1((c.vst.plugin ? c.vst.plugin->state() : c.vst.state).toBase64()));
            o.insert(QStringLiteral("vst"), v);
        }
        channels.append(o);
    }
    for (const Pattern &p : m_patterns) {
        QJsonObject data;
        for (auto it = p.data.constBegin(); it != p.data.constEnd(); ++it) {
            QJsonArray steps, notes;
            for (double v : it->steps)
                steps.append(v);
            for (const PatNote &n : it->notes)
                notes.append(QJsonObject{{QStringLiteral("step"), n.step}, {QStringLiteral("len"), n.len}, {QStringLiteral("pitch"), n.pitch}, {QStringLiteral("vel"), n.vel}});
            data.insert(QString::number(it.key()), QJsonObject{{QStringLiteral("steps"), steps}, {QStringLiteral("notes"), notes}});
        }
        patterns.append(QJsonObject{{QStringLiteral("id"), p.id}, {QStringLiteral("name"), p.name}, {QStringLiteral("bars"), p.bars}, {QStringLiteral("data"), data}});
    }
    return QJsonObject{{QStringLiteral("inserts"), inserts}, {QStringLiteral("channels"), channels}, {QStringLiteral("patterns"), patterns},
                       {QStringLiteral("current"), m_curPattern}, {QStringLiteral("swing"), m_swing}};
}

void Studio::rackFromJson(const QJsonObject &o, const QHash<int, Channel> &oldChannels)
{
    for (const QJsonValue &v : o.value(QStringLiteral("channels")).toArray()) {
        const QJsonObject co = v.toObject();
        Channel c;
        c.id = co.value(QStringLiteral("id")).toInt();
        c.name = co.value(QStringLiteral("name")).toString();
        c.color = co.value(QStringLiteral("color")).toInt() % Colors;
        c.insert = co.value(QStringLiteral("insert")).toInt();
        c.volume = co.value(QStringLiteral("volume")).toDouble();
        c.pan = co.value(QStringLiteral("pan")).toDouble();
        c.mute = co.value(QStringLiteral("mute")).toBool();
        c.kind = co.value(QStringLiteral("kind")).toString();
        c.kit = co.value(QStringLiteral("kit")).toString();
        c.row = co.value(QStringLiteral("row")).toString();
        c.file = co.value(QStringLiteral("file")).toString();
        c.inst = co.value(QStringLiteral("inst")).toString();
        c.root = co.value(QStringLiteral("root")).toInt(60);
        c.oneShot = co.value(QStringLiteral("oneShot")).toBool(true);
        const QJsonObject vo = co.value(QStringLiteral("vst")).toObject();
        const bool hasState = vo.contains(QStringLiteral("state"));
        if (c.kind == QLatin1String("vst")) {
            c.vst.id = c.id;
            c.vst.info = infoFrom(vo);
            if (hasState)
                c.vst.state = QByteArray::fromBase64(vo.value(QStringLiteral("state")).toString().toLatin1());
            else if (m_slotMemo.contains(c.id))
                c.vst.state = m_slotMemo.value(c.id);
        }
        // Cofanie: ten sam instrument gra dalej
        if (const auto it = oldChannels.constFind(c.id); it != oldChannels.constEnd() && !hasState && it->kind == c.kind
            && it->kit == c.kit && it->row == c.row && it->file == c.file && it->inst == c.inst && it->root == c.root) {
            c.instrument = it->instrument;
            c.vst.plugin = it->vst.plugin;
        }
        if (c.kind == QLatin1String("sampler") && !m_sources.contains(c.file))
            loadSources({c.file});
        if (insertIndex(c.insert) < 0)
            c.insert = newInsert(c.name, c.color);
        m_nextId = std::max(m_nextId, c.id + 1);
        m_channels.append(c);
    }
    for (const QJsonValue &v : o.value(QStringLiteral("patterns")).toArray()) {
        const QJsonObject po = v.toObject();
        Pattern p;
        p.id = po.value(QStringLiteral("id")).toInt();
        p.name = po.value(QStringLiteral("name")).toString();
        p.bars = std::clamp(po.value(QStringLiteral("bars")).toInt(1), 1, 32);
        const QJsonObject data = po.value(QStringLiteral("data")).toObject();
        for (auto it = data.constBegin(); it != data.constEnd(); ++it) {
            PatData d;
            const QJsonObject dv = it.value().toObject();
            for (const QJsonValue &s : dv.value(QStringLiteral("steps")).toArray())
                d.steps.append(s.toDouble());
            for (const QJsonValue &n : dv.value(QStringLiteral("notes")).toArray()) {
                const QJsonObject no = n.toObject();
                d.notes.append({no.value(QStringLiteral("step")).toDouble(), no.value(QStringLiteral("len")).toDouble(1), no.value(QStringLiteral("pitch")).toInt(60), no.value(QStringLiteral("vel")).toDouble(0.8)});
            }
            p.data.insert(it.key().toInt(), d);
        }
        m_nextId = std::max(m_nextId, p.id + 1);
        m_patterns.append(p);
    }
    m_curPattern = o.value(QStringLiteral("current")).toInt();
    m_swing = std::clamp(o.value(QStringLiteral("swing")).toDouble(), 0.0, 0.5);
    // Ścieżka bez insertu (uszkodzony plik) dostaje własny
    for (Track &t : m_tracks)
        if (insertIndex(t.insert) < 0)
            t.insert = newInsert(t.name, t.color);
}
