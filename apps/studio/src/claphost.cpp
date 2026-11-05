// Host wtyczek CLAP (otwarty format, nagłówki MIT). Interfejs jak VST3: parametry 0…1, stan, okno X11.
#include "plugin.h"
#include "pluginwindow.h"

#include <clap/clap.h>

#include <QCoreApplication>
#include <QFileInfo>
#include <QHash>
#include <QSocketNotifier>
#include <QTimer>
#include <algorithm>
#include <cstring>
#include <dlfcn.h>
#include <map>
#include <thread>
#include <vector>

namespace Clap {

using namespace Plug;

namespace {

const clap_plugin_entry_t *entryOf(const QString &path, QString *error)
{
    static auto *loaded = new QHash<QString, const clap_plugin_entry_t *>;      // zostają do końca programu
    if (const auto it = loaded->constFind(path); it != loaded->constEnd())
        return it.value();
    void *h = dlopen(path.toUtf8().constData(), RTLD_NOW | RTLD_LOCAL);
    if (!h) {
        if (error)
            *error = QString::fromUtf8(dlerror());
        return nullptr;
    }
    auto *e = static_cast<const clap_plugin_entry_t *>(dlsym(h, "clap_entry"));
    if (!e || !e->init(path.toUtf8().constData())) {
        if (error)
            *error = QStringLiteral("To nie jest wtyczka CLAP: %1").arg(path);
        return nullptr;
    }
    loaded->insert(path, e);
    return e;
}

constexpr unsigned QueueSize = 1024;
struct ParamMsg { clap_id id; double plain; };

}

class Instance : public Plugin
{
public:
    static std::unique_ptr<Plugin> load(const Info &info, double rate, int maxBlock, QString *error);
    ~Instance() override;
    void process(float *l, float *r, int n, const Note *notes, int noteCount, const Transport &t, const float *sideL, const float *sideR) override;
    void automate(unsigned id, double value) override;
    bool hasSidechain() const override { return m_aux >= 0; }
    QList<Param> params() const override;
    void setParam(unsigned id, double value) override;
    QByteArray state() const override;
    bool setState(const QByteArray &data) override;
    bool hasEditor() const override;
    bool openEditor() override;
    void closeEditor() override;

private:
    struct Range { double min, max; };
    static const void *extension(const clap_host_t *h, const char *id);
    static Instance *self(const clap_host_t *h) { return static_cast<Instance *>(h->host_data); }
    void refreshLatency();
    double plainOf(unsigned id, double n) const
    {
        const auto it = m_ranges.find(id);
        return it == m_ranges.end() ? n : it->second.min + (it->second.max - it->second.min) * n;
    }
    clap_host_t m_host{};
    const clap_plugin_t *m_p = nullptr;
    const clap_plugin_params_t *m_params = nullptr;
    const clap_plugin_state_t *m_state = nullptr;
    const clap_plugin_gui_t *m_gui = nullptr;
    const clap_plugin_latency_t *m_lat = nullptr;
    const clap_plugin_timer_support_t *m_timerExt = nullptr;
    const clap_plugin_posix_fd_support_t *m_fdExt = nullptr;
    std::map<clap_id, Range> m_ranges;
    int m_maxBlock = 2048, m_inCh = 0, m_outCh = 2, m_aux = -1, m_auxCh = 0;
    double m_rate = 48000;
    bool m_started = false, m_guiOpen = false;
    std::vector<float> m_inBuf, m_outBuf, m_auxBuf;
    std::vector<clap_event_note_t> m_notes;
    std::vector<clap_event_param_value_t> m_values;
    std::vector<const clap_event_header_t *> m_events;
    clap_event_transport_t m_transport{};
    ParamMsg m_queue[QueueSize];
    std::atomic<unsigned> m_qw{0}, m_qr{0};
    ParamMsg m_rt[64];
    int m_rtCount = 0;
    std::atomic_flag m_busy = ATOMIC_FLAG_INIT;
    std::thread::id m_mainThread;
    std::unique_ptr<PluginWindow> m_window;
    QHash<clap_id, QTimer *> m_timers;
    clap_id m_nextTimer = 1;
    QHash<int, QSocketNotifier *> m_fds;
};

const void *Instance::extension(const clap_host_t *, const char *id)
{
    static const clap_host_latency_t latency{[](const clap_host_t *h) { self(h)->refreshLatency(); }};
    static const clap_host_params_t params{[](const clap_host_t *, clap_param_rescan_flags) {}, [](const clap_host_t *, clap_id, clap_param_clear_flags) {},
                                           [](const clap_host_t *) {}};
    static const clap_host_thread_check_t threads{
        [](const clap_host_t *h) { return std::this_thread::get_id() == self(h)->m_mainThread; },
        [](const clap_host_t *h) { return std::this_thread::get_id() != self(h)->m_mainThread; }};
    static const clap_host_gui_t gui{
        [](const clap_host_t *) {},
        [](const clap_host_t *h, uint32_t w, uint32_t ht) {
            if (self(h)->m_window)
                self(h)->m_window->resize(int(w), int(ht));
            return true;
        },
        [](const clap_host_t *) { return true; }, [](const clap_host_t *) { return true; },
        [](const clap_host_t *h, bool) { self(h)->closeEditor(); }};
    static const clap_host_timer_support_t timers{
        [](const clap_host_t *h, uint32_t ms, clap_id *out) {
            Instance *i = self(h);
            const clap_id id = i->m_nextTimer++;
            auto *t = new QTimer;
            t->setInterval(int(std::max<uint32_t>(ms, 10)));
            QObject::connect(t, &QTimer::timeout, t, [i, id] {
                if (i->m_timerExt)
                    i->m_timerExt->on_timer(i->m_p, id);
            });
            t->start();
            i->m_timers.insert(id, t);
            *out = id;
            return true;
        },
        [](const clap_host_t *h, clap_id id) {
            delete self(h)->m_timers.take(id);
            return true;
        }};
    static const clap_host_posix_fd_support_t fds{
        [](const clap_host_t *h, int fd, clap_posix_fd_flags_t) {
            Instance *i = self(h);
            auto *n = new QSocketNotifier(fd, QSocketNotifier::Read);
            QObject::connect(n, &QSocketNotifier::activated, n, [i, fd] {
                if (i->m_fdExt)
                    i->m_fdExt->on_fd(i->m_p, fd, CLAP_POSIX_FD_READ);
            });
            i->m_fds.insert(fd, n);
            return true;
        },
        [](const clap_host_t *, int, clap_posix_fd_flags_t) { return true; },
        [](const clap_host_t *h, int fd) {
            delete self(h)->m_fds.take(fd);
            return true;
        }};
    if (!strcmp(id, CLAP_EXT_LATENCY))
        return &latency;
    if (!strcmp(id, CLAP_EXT_PARAMS))
        return &params;
    if (!strcmp(id, CLAP_EXT_THREAD_CHECK))
        return &threads;
    if (!strcmp(id, CLAP_EXT_GUI))
        return &gui;
    if (!strcmp(id, CLAP_EXT_TIMER_SUPPORT))
        return &timers;
    if (!strcmp(id, CLAP_EXT_POSIX_FD_SUPPORT))
        return &fds;
    return nullptr;
}

void Instance::refreshLatency()
{
    if (m_lat)
        m_latency.store(int(m_lat->get(m_p)));
}

std::unique_ptr<Plugin> Instance::load(const Info &info, double rate, int maxBlock, QString *error)
{
    auto fail = [error](const QString &e) {
        if (error)
            *error = e;
        return std::unique_ptr<Plugin>();
    };
    const clap_plugin_entry_t *entry = entryOf(info.path, error);
    if (!entry)
        return {};
    auto *factory = static_cast<const clap_plugin_factory_t *>(entry->get_factory(CLAP_PLUGIN_FACTORY_ID));
    if (!factory)
        return fail(QStringLiteral("Brak fabryki wtyczek: %1").arg(info.name));
    std::unique_ptr<Instance> p(new Instance);
    p->m_info = info;
    p->m_rate = rate;
    p->m_maxBlock = maxBlock;
    p->m_mainThread = std::this_thread::get_id();
    clap_host_t &h = p->m_host;
    h.clap_version = CLAP_VERSION;
    h.host_data = p.get();
    h.name = "Studio Aster";
    h.vendor = "Aster";
    h.url = "";
    h.version = "1.0";
    h.get_extension = extension;
    h.request_restart = [](const clap_host_t *) {};
    h.request_process = [](const clap_host_t *) {};
    h.request_callback = [](const clap_host_t *host) {
        Instance *i = self(host);
        QMetaObject::invokeMethod(qApp, [i] { i->m_p->on_main_thread(i->m_p); }, Qt::QueuedConnection);
    };
    p->m_p = factory->create_plugin(factory, &h, info.uid.toUtf8().constData());
    if (!p->m_p || !p->m_p->init(p->m_p))
        return fail(QStringLiteral("Wtyczka nie chce się uruchomić: %1").arg(info.name));
    const clap_plugin_t *pl = p->m_p;
    auto ext = [pl](const char *id) { return pl->get_extension(pl, id); };
    p->m_params = static_cast<const clap_plugin_params_t *>(ext(CLAP_EXT_PARAMS));
    p->m_state = static_cast<const clap_plugin_state_t *>(ext(CLAP_EXT_STATE));
    p->m_gui = static_cast<const clap_plugin_gui_t *>(ext(CLAP_EXT_GUI));
    p->m_lat = static_cast<const clap_plugin_latency_t *>(ext(CLAP_EXT_LATENCY));
    p->m_timerExt = static_cast<const clap_plugin_timer_support_t *>(ext(CLAP_EXT_TIMER_SUPPORT));
    p->m_fdExt = static_cast<const clap_plugin_posix_fd_support_t *>(ext(CLAP_EXT_POSIX_FD_SUPPORT));
    // Porty: główne wejście i wyjście, pierwsze dodatkowe wejście to sidechain
    if (auto *ports = static_cast<const clap_plugin_audio_ports_t *>(ext(CLAP_EXT_AUDIO_PORTS))) {
        clap_audio_port_info_t pi{};
        const uint32_t ins = ports->count(pl, true);
        for (uint32_t i = 0; i < ins; ++i) {
            if (!ports->get(pl, i, true, &pi))
                continue;
            if (i == 0)
                p->m_inCh = int(pi.channel_count);
            else if (p->m_aux < 0) {
                p->m_aux = int(i);
                p->m_auxCh = int(pi.channel_count);
            }
        }
        if (ports->count(pl, false) > 0 && ports->get(pl, 0, false, &pi))
            p->m_outCh = int(pi.channel_count);
    }
    p->m_inBuf.assign(size_t(std::max(p->m_inCh, 1)) * size_t(maxBlock), 0.f);
    p->m_outBuf.assign(size_t(std::max(p->m_outCh, 1)) * size_t(maxBlock), 0.f);
    p->m_auxBuf.assign(size_t(std::max(p->m_auxCh, 1)) * size_t(maxBlock), 0.f);
    p->m_notes.reserve(1024);
    p->m_values.reserve(QueueSize + 64);
    p->m_events.reserve(QueueSize + 1200);
    if (p->m_params)
        for (uint32_t i = 0, n = p->m_params->count(pl); i < n; ++i) {
            clap_param_info_t pi{};
            if (p->m_params->get_info(pl, i, &pi))
                p->m_ranges[pi.id] = {pi.min_value, pi.max_value};
        }
    if (!pl->activate(pl, rate, 1, uint32_t(maxBlock)))
        return fail(QStringLiteral("Wtyczka nie chce się włączyć: %1").arg(info.name));
    p->refreshLatency();
    return std::unique_ptr<Plugin>(p.release());
}

Instance::~Instance()
{
    closeEditor();
    if (m_p) {
        if (m_started)
            m_p->stop_processing(m_p);
        m_p->deactivate(m_p);
        m_p->destroy(m_p);
    }
    qDeleteAll(m_timers);
    qDeleteAll(m_fds);
}

void Instance::automate(unsigned id, double value)
{
    if (m_rtCount < 64)
        m_rt[m_rtCount++] = {id, plainOf(id, std::clamp(value, 0.0, 1.0))};
}

void Instance::process(float *l, float *r, int n, const Note *notes, int noteCount, const Transport &t, const float *sideL, const float *sideR)
{
    if (m_busy.test_and_set(std::memory_order_acquire))
        return;
    if (!m_started)
        m_started = m_p->start_processing(m_p);
    n = std::min(n, m_maxBlock);
    // Zdarzenia: parametry na początku bloku, nuty po kolei
    m_notes.clear();
    m_values.clear();
    m_events.clear();
    auto value = [&](clap_id id, double v) {
        clap_event_param_value_t e{};
        e.header = {sizeof e, 0, CLAP_CORE_EVENT_SPACE_ID, CLAP_EVENT_PARAM_VALUE, 0};
        e.param_id = id;
        e.note_id = -1;
        e.port_index = -1;
        e.channel = -1;
        e.key = -1;
        e.value = v;
        m_values.push_back(e);
    };
    unsigned rd = m_qr.load(std::memory_order_relaxed);
    const unsigned wr = m_qw.load(std::memory_order_acquire);
    for (; rd != wr; ++rd)
        value(m_queue[rd % QueueSize].id, m_queue[rd % QueueSize].plain);
    m_qr.store(rd, std::memory_order_release);
    for (int k = 0; k < m_rtCount; ++k)
        value(m_rt[k].id, m_rt[k].plain);
    m_rtCount = 0;
    for (const auto &e : m_values)
        m_events.push_back(&e.header);
    for (int k = 0; k < noteCount; ++k) {
        clap_event_note_t e{};
        e.header = {sizeof e, uint32_t(notes[k].offset), CLAP_CORE_EVENT_SPACE_ID, uint16_t(notes[k].on ? CLAP_EVENT_NOTE_ON : CLAP_EVENT_NOTE_OFF), 0};
        e.note_id = -1;
        e.port_index = 0;
        e.channel = 0;
        e.key = int16_t(notes[k].pitch);
        e.velocity = notes[k].velocity;
        m_notes.push_back(e);
    }
    for (const auto &e : m_notes)
        m_events.push_back(&e.header);
    clap_input_events_t in{&m_events, [](const clap_input_events_t *l2) { return uint32_t(static_cast<std::vector<const clap_event_header_t *> *>(l2->ctx)->size()); },
                           [](const clap_input_events_t *l2, uint32_t i) { return (*static_cast<std::vector<const clap_event_header_t *> *>(l2->ctx))[i]; }};
    clap_output_events_t out{nullptr, [](const clap_output_events_t *, const clap_event_header_t *) { return true; }};

    clap_event_transport_t &tr = m_transport;
    tr.header = {sizeof tr, 0, CLAP_CORE_EVENT_SPACE_ID, CLAP_EVENT_TRANSPORT, 0};
    tr.flags = CLAP_TRANSPORT_HAS_TEMPO | CLAP_TRANSPORT_HAS_BEATS_TIMELINE | CLAP_TRANSPORT_HAS_TIME_SIGNATURE | (t.playing ? CLAP_TRANSPORT_IS_PLAYING : 0);
    tr.tempo = t.bpm;
    tr.song_pos_beats = clap_beattime(double(t.samples) / m_rate * t.bpm / 60.0 * double(CLAP_BEATTIME_FACTOR));
    tr.tsig_num = uint16_t(t.beatsPerBar);
    tr.tsig_denom = 4;

    float *inPtr[2], *outPtr[2], *auxPtr[2];
    for (int c = 0; c < std::min(m_inCh, 2); ++c) {
        inPtr[c] = m_inBuf.data() + size_t(c) * size_t(m_maxBlock);
        std::memcpy(inPtr[c], c ? r : l, size_t(n) * sizeof(float));
    }
    for (int c = 0; c < std::min(m_outCh, 2); ++c)
        outPtr[c] = m_outBuf.data() + size_t(c) * size_t(m_maxBlock);
    clap_audio_buffer_t ain[2]{}, aout{};
    ain[0].data32 = inPtr;
    ain[0].channel_count = uint32_t(std::min(m_inCh, 2));
    aout.data32 = outPtr;
    aout.channel_count = uint32_t(std::min(m_outCh, 2));
    uint32_t inputs = m_inCh > 0 ? 1 : 0;
    if (m_aux == 1) {
        for (int c = 0; c < std::min(m_auxCh, 2); ++c) {
            auxPtr[c] = m_auxBuf.data() + size_t(c) * size_t(m_maxBlock);
            const float *from = c ? sideR : sideL;
            if (from)
                std::memcpy(auxPtr[c], from, size_t(n) * sizeof(float));
            else
                std::memset(auxPtr[c], 0, size_t(n) * sizeof(float));
        }
        ain[1].data32 = auxPtr;
        ain[1].channel_count = uint32_t(std::min(m_auxCh, 2));
        inputs = 2;
    }
    clap_process_t pc{};
    pc.steady_time = t.samples;
    pc.frames_count = uint32_t(n);
    pc.transport = &tr;
    pc.audio_inputs = ain;
    pc.audio_outputs = &aout;
    pc.audio_inputs_count = inputs;
    pc.audio_outputs_count = 1;
    pc.in_events = &in;
    pc.out_events = &out;
    m_p->process(m_p, &pc);
    std::memcpy(l, outPtr[0], size_t(n) * sizeof(float));
    std::memcpy(r, m_outCh > 1 ? outPtr[1] : outPtr[0], size_t(n) * sizeof(float));
    m_busy.clear(std::memory_order_release);
}

QList<Param> Instance::params() const
{
    QList<Param> out;
    if (!m_params)
        return out;
    for (uint32_t i = 0, n = m_params->count(m_p); i < n; ++i) {
        clap_param_info_t pi{};
        if (!m_params->get_info(m_p, i, &pi) || (pi.flags & CLAP_PARAM_IS_HIDDEN))
            continue;
        double v = pi.default_value;
        m_params->get_value(m_p, pi.id, &v);
        const double span = pi.max_value - pi.min_value;
        out << Param{pi.id, QString::fromUtf8(pi.name), QString(), span > 0 ? (v - pi.min_value) / span : 0, bool(pi.flags & CLAP_PARAM_IS_AUTOMATABLE)};
    }
    return out;
}

void Instance::setParam(unsigned id, double value)
{
    const unsigned w = m_qw.load(std::memory_order_relaxed);
    if (w - m_qr.load(std::memory_order_acquire) >= QueueSize)
        return;
    m_queue[w % QueueSize] = {id, plainOf(id, std::clamp(value, 0.0, 1.0))};
    m_qw.store(w + 1, std::memory_order_release);
}

QByteArray Instance::state() const
{
    QByteArray out;
    if (!m_state)
        return out;
    clap_ostream_t s{&out, [](const clap_ostream_t *o, const void *buf, uint64_t size) {
                         static_cast<QByteArray *>(o->ctx)->append(static_cast<const char *>(buf), qsizetype(size));
                         return int64_t(size);
                     }};
    m_state->save(m_p, &s);
    return out;
}

bool Instance::setState(const QByteArray &data)
{
    if (!m_state)
        return false;
    struct Reader { const QByteArray *d; qsizetype at; } r{&data, 0};
    clap_istream_t s{&r, [](const clap_istream_t *i, void *buf, uint64_t size) {
                         auto *rd = static_cast<Reader *>(i->ctx);
                         const qsizetype n = std::min<qsizetype>(qsizetype(size), rd->d->size() - rd->at);
                         std::memcpy(buf, rd->d->constData() + rd->at, size_t(n));
                         rd->at += n;
                         return int64_t(n);
                     }};
    while (m_busy.test_and_set(std::memory_order_acquire)) {}
    const bool ok = m_state->load(m_p, &s);
    m_busy.clear(std::memory_order_release);
    return ok;
}

bool Instance::hasEditor() const
{
    return m_gui && m_gui->is_api_supported(m_p, CLAP_WINDOW_API_X11, false);
}

bool Instance::openEditor()
{
    if (m_guiOpen) {
        m_window->raise();
        return true;
    }
    if (!hasEditor() || !m_gui->create(m_p, CLAP_WINDOW_API_X11, false))
        return false;
    uint32_t w = 640, h = 400;
    m_gui->get_size(m_p, &w, &h);
    m_window = std::make_unique<PluginWindow>(m_info.name, int(w), int(h), [this] { closeEditor(); });
    if (!m_window->ok()) {
        m_window.reset();
        m_gui->destroy(m_p);
        return false;
    }
    clap_window_t win{};
    win.api = CLAP_WINDOW_API_X11;
    win.x11 = m_window->id();
    m_gui->set_parent(m_p, &win);
    m_gui->show(m_p);
    m_guiOpen = true;
    return true;
}

void Instance::closeEditor()
{
    if (!m_guiOpen)
        return;
    m_guiOpen = false;
    m_gui->hide(m_p);
    m_gui->destroy(m_p);
    m_window.reset();
}

QList<Info> scanFile(const QString &file)
{
    QList<Info> out;
    QString err;
    const QString path = QFileInfo(file).canonicalFilePath();
    const clap_plugin_entry_t *entry = entryOf(path, &err);
    auto *f = entry ? static_cast<const clap_plugin_factory_t *>(entry->get_factory(CLAP_PLUGIN_FACTORY_ID)) : nullptr;
    if (!f)
        return out;
    for (uint32_t i = 0, n = f->get_plugin_count(f); i < n; ++i) {
        const clap_plugin_descriptor_t *d = f->get_plugin_descriptor(f, i);
        Info info;
        info.format = QStringLiteral("clap");
        info.path = path;
        info.uid = QString::fromUtf8(d->id);
        info.name = QString::fromUtf8(d->name);
        info.vendor = QString::fromUtf8(d->vendor ? d->vendor : "");
        QStringList features;
        for (const char *const *ft = d->features; ft && *ft; ++ft)
            features << QString::fromUtf8(*ft);
        info.category = features.join(QLatin1Char('|'));
        info.instrument = features.contains(QLatin1String(CLAP_PLUGIN_FEATURE_INSTRUMENT));
        out << info;
    }
    return out;
}

std::unique_ptr<Plugin> load(const Info &info, double rate, int maxBlock, QString *error)
{
    return Instance::load(info, rate, maxBlock, error);
}

}
