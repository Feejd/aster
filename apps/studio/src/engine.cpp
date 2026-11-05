#include "engine.h"

#include <QDateTime>
#include <QFile>
#include <QMetaObject>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <pipewire/pipewire.h>
#include <sndfile.h>
#include <spa/param/audio/format-utils.h>

// ——— Mikser ———

static inline void raisePeak(std::atomic<float> &a, float v)
{
    if (v > a.load(std::memory_order_relaxed))
        a.store(v, std::memory_order_relaxed);
}

void Renderer::process(const Snapshot *s, long long pos, int n, float *out, bool click, Meters *meters, int rate, bool clips)
{
    while (n > 0) {
        const int k = std::min(n, MaxBlock);
        block(s, pos, k, out, click, meters, rate, clips);
        m_monPos += k;
        pos += k;
        out += 2 * k;
        n -= k;
    }
}

void Renderer::block(const Snapshot *s, long long pos, int n, float *out, bool click, Meters *meters, int rate, bool clips)
{
    std::fill_n(m_l, n, 0.f);
    std::fill_n(m_r, n, 0.f);
    std::fill_n(m_rl, n, 0.f);
    std::fill_n(m_rr, n, 0.f);
    std::fill_n(m_el, n, 0.f);
    std::fill_n(m_er, n, 0.f);
    bool echo = false;
    const long long declick = rate / 500;   // 2 ms łagodnego wejścia i wyjścia na brzegach klipu — bez trzasków
    bool reverb = false;

    if (s) {
        for (size_t ti = 0; ti < s->tracks.size(); ++ti) {
            const TrackRT &t = s->tracks[ti];
            reverb |= t.send > 0;
            echo |= t.echo > 0;
            bool any = false;
            // Granie na żywo na tej ścieżce — wchodzi przed efekty, jak klipy
            if (m_live && m_live->any(int(ti))) {
                std::fill_n(m_tl, n, 0.f);
                std::fill_n(m_tr, n, 0.f);
                any = true;
                m_live->render(int(ti), m_tl, m_tr, n);
            }
            if (!t.audible)
                continue;
            // Odsłuch mikrofonu na uzbrojonej ścieżce — słychać od razu z jej efektami (np. autotune)
            if (m_mon && int(ti) == m_monTrack && m_monPos < m_monN) {
                if (!any) {
                    std::fill_n(m_tl, n, 0.f);
                    std::fill_n(m_tr, n, 0.f);
                    any = true;
                }
                const int k = std::min(n, m_monN - m_monPos);
                for (int i = 0; i < k; ++i) {
                    m_tl[i] += m_mon[m_monPos + i];
                    m_tr[i] += m_mon[m_monPos + i];
                }
            }
            for (const ClipRT &c : t.clips) {
                if (!clips)
                    break;
                const long long a = std::max(pos, c.start);
                const long long b = std::min(pos + n, c.start + c.length);
                if (a >= b || !c.src || c.srcLen <= 0)
                    continue;
                if (!any) {
                    std::fill_n(m_tl, n, 0.f);
                    std::fill_n(m_tr, n, 0.f);
                    any = true;
                }
                const AudioSource &src = *c.src;
                const long long fin = std::max(declick, c.fadeIn), fout = std::max(declick, c.fadeOut);
                for (long long f = a; f < b; ++f) {
                    const long long t0 = f - c.start;
                    const long long si = c.srcStart + (c.loop ? (t0 + c.offset) % c.srcLen : t0);
                    if (si < 0 || si >= src.frames)
                        continue;
                    float g = c.gain;
                    if (t0 < fin)
                        g *= std::sin(1.5707963f * float(t0) / fin);
                    if (c.length - t0 < fout)
                        g *= std::sin(1.5707963f * float(c.length - t0) / fout);
                    m_tl[f - pos] += src.at(si, 0) * g;
                    m_tr[f - pos] += src.at(si, 1) * g;
                }
            }
            // Wtyczka gra też po końcu klipu (ogony pogłosu i echa)
            if (!any && !t.fx.empty()) {
                std::fill_n(m_tl, n, 0.f);
                std::fill_n(m_tr, n, 0.f);
                any = true;
            }
            if (!any)
                continue;

            // Efekty ścieżki: autotune → korektor → de-esser → przester → kompresor → sztuczny dubel → głośność i panorama → wysyłka do pogłosu
            if (ti < size_t(MaxTracks)) {
                if (t.tune.on)
                    m_tune[ti].process(m_tl, m_tr, n, t.tune, rate);
                for (int k = 0; k < 4; ++k) {
                    if (t.eq[k].flat())
                        continue;
                    BiquadState &zl = m_eq[ti][k][0], &zr = m_eq[ti][k][1];
                    for (int i = 0; i < n; ++i) {
                        m_tl[i] = zl.run(t.eq[k], m_tl[i]);
                        m_tr[i] = zr.run(t.eq[k], m_tr[i]);
                    }
                }
                if (t.deess > 0)
                    m_deess[ti].process(m_tl, m_tr, n, t.deessLp, t.deessHp, t.deess, rate);
                if (t.drive > 0) {
                    // Ciepło / przester: miękkie nasycenie, poziom wyrównany do wejścia
                    const float k = 1.f + 6.f * t.drive, norm = 1.f / std::tanh(k);
                    for (int i = 0; i < n; ++i) {
                        m_tl[i] = std::tanh(m_tl[i] * k) * norm * (1.f - 0.35f * t.drive) + m_tl[i] * 0.35f * t.drive;
                        m_tr[i] = std::tanh(m_tr[i] * k) * norm * (1.f - 0.35f * t.drive) + m_tr[i] * 0.35f * t.drive;
                    }
                }
                if (t.comp.on) {
                    CompState &cs = m_comp[ti];
                    for (int i = 0; i < n; ++i) {
                        const float g = cs.process(t.comp, std::max(std::fabs(m_tl[i]), std::fabs(m_tr[i])), rate);
                        m_tl[i] *= g;
                        m_tr[i] *= g;
                    }
                }
                if (t.dbl > 0)
                    m_dbl[ti].process(m_tl, m_tr, n, t.dbl, rate);
                else
                    m_dbl[ti].idle();
                if (!t.fx.empty()) {
                    const Vst3::Transport tp{s->bpm, std::max(0LL, pos), clips, s->beatsPerBar};
                    for (Vst3::Plugin *p : t.fx)
                        p->process(m_tl, m_tr, n, nullptr, 0, tp);
                }
            }
            float pl = 0.f, pr = 0.f;
            for (int i = 0; i < n; ++i) {
                const float l = m_tl[i] * t.gainL, r = m_tr[i] * t.gainR;
                m_l[i] += l;
                m_r[i] += r;
                if (t.send > 0) {
                    m_rl[i] += l * t.send;
                    m_rr[i] += r * t.send;
                }
                if (t.echo > 0) {
                    m_el[i] += l * t.echo;
                    m_er[i] += r * t.echo;
                }
                pl = std::max(pl, std::fabs(l));
                pr = std::max(pr, std::fabs(r));
            }
            if (meters && ti < size_t(MaxTracks)) {
                raisePeak((*meters)[ti][0], pl);
                raisePeak((*meters)[ti][1], pr);
            }
        }
    }

    if (m_live && s)
        m_live->dropFrom(int(s->tracks.size()));

    // Wspólny pogłos (gra dalej, gdy klipy się skończą — wybrzmiewanie)
    if (reverb) {
        if (m_reverbRate != rate) {
            m_reverb.setup(rate, s->reverbSize);
            m_reverbRate = rate;
        }
        m_reverb.setSize(s->reverbSize);
        m_reverb.process(m_rl, m_rr, m_l, m_r, n);
    }
    if (echo || (s && s->echoDelay > 0)) {
        if (s)
            m_echo.process(m_el, m_er, m_l, m_r, n, int(s->echoDelay * (rate / 48000.0)), s->echoFeedback);
    }

    // Suma: głośność → mastering (korektor, kompresor, szerokość, dociśnięcie) → ogranicznik z wyprzedzeniem
    const float master = s ? s->master : 1.f;
    const MasterParams mp = s ? s->mastering : MasterParams{};
    const float release = 1.f - std::exp(-1.f / (0.15f * rate));
    float pl = 0.f, pr = 0.f;
    for (int i = 0; i < n; ++i) {
        float l = m_l[i] * master, r = m_r[i] * master;
        if (!mp.low.flat()) {
            l = m_mEq[0][0].run(mp.low, l);
            r = m_mEq[0][1].run(mp.low, r);
        }
        if (!mp.high.flat()) {
            l = m_mEq[1][0].run(mp.high, l);
            r = m_mEq[1][1].run(mp.high, r);
        }
        if (mp.comp.on) {
            const float g = m_mComp.process(mp.comp, std::max(std::fabs(l), std::fabs(r)), rate);
            l *= g;
            r *= g;
        }
        if (mp.width != 1.f) {
            const float mid = 0.5f * (l + r), side = 0.5f * (l - r) * mp.width;
            l = mid + side;
            r = mid - side;
        }
        l *= mp.drive;
        r *= mp.drive;
        m_limiter.process(l, r, m_ceiling, release);
        m_l[i] = l;
        m_r[i] = r;
        pl = std::max(pl, std::fabs(l));
        pr = std::max(pr, std::fabs(r));
    }
    // Wskaźnik sumy po ograniczniku (to, co naprawdę wychodzi)
    if (meters) {
        raisePeak((*meters)[MaxTracks][0], pl);
        raisePeak((*meters)[MaxTracks][1], pr);
    }

    // Metronom (poza miernikiem sumy): wyższy dźwięk na pierwszą miarę taktu
    if (click) {
        const double fpb = rate * 60.0 / (s ? s->bpm : 120.0);
        const int bpb = s ? std::max(1, s->beatsPerBar) : 4;
        const long long len = rate / 16;
        for (int i = 0; i < n; ++i) {
            const long long p = pos + i;
            const double beat = std::floor(double(p) / fpb);
            const long long off = p - std::llround(beat * fpb);
            if (off < 0 || off >= len)
                continue;
            const long long bi = (long long)beat;
            const bool accent = ((bi % bpb) + bpb) % bpb == 0;
            const float tt = float(off) / rate;
            const float v = std::sin(6.2831853f * (accent ? 1760.f : 1320.f) * tt) * std::exp(-tt * 45.f) * (accent ? 0.7f : 0.5f) * (s ? s->click : 0.7f);
            m_l[i] += v;
            m_r[i] += v;
        }
    }

    for (int i = 0; i < n; ++i) {
        out[2 * i] = m_l[i];
        out[2 * i + 1] = m_r[i];
    }
}

// ——— Bufor pierścieniowy ———

size_t SpscRing::write(const float *data, size_t n)
{
    const size_t cap = m_buf.size();
    const size_t w = m_write.load(std::memory_order_relaxed), r = m_read.load(std::memory_order_acquire);
    n = std::min(n, cap - 1 - (w - r + cap) % cap);
    for (size_t i = 0; i < n; ++i)
        m_buf[(w + i) % cap] = data[i];
    m_write.store((w + n) % cap, std::memory_order_release);
    return n;
}

size_t SpscRing::read(float *data, size_t n)
{
    const size_t cap = m_buf.size();
    const size_t r = m_read.load(std::memory_order_relaxed), w = m_write.load(std::memory_order_acquire);
    n = std::min(n, (w - r + cap) % cap);
    for (size_t i = 0; i < n; ++i)
        data[i] = m_buf[(r + i) % cap];
    m_read.store((r + n) % cap, std::memory_order_release);
    return n;
}

size_t SpscRing::available() const
{
    const size_t cap = m_buf.size();
    return (m_write.load() - m_read.load() + cap) % cap;
}

// ——— PipeWire ———

struct EngineHooks
{
    spa_hook registry{}, out{}, in{};
};

struct EngineCallbacks
{
    static void outProcess(void *d) { static_cast<Engine *>(d)->onPlayback(); }
    static void inProcess(void *d) { static_cast<Engine *>(d)->onCapture(); }
    static void stateChanged(void *d, pw_stream_state, pw_stream_state state, const char *err)
    {
        if (state != PW_STREAM_STATE_ERROR)
            return;
        auto *e = static_cast<Engine *>(d);
        const QString msg = QString::fromUtf8(err ? err : "");
        QMetaObject::invokeMethod(e, [e, msg] { emit e->streamError(msg); }, Qt::QueuedConnection);
    }
    static void global(void *d, uint32_t id, uint32_t, const char *type, uint32_t, const spa_dict *props)
    {
        if (!props || std::strcmp(type, PW_TYPE_INTERFACE_Node) != 0)
            return;
        const char *cls = spa_dict_lookup(props, PW_KEY_MEDIA_CLASS);
        if (!cls)
            return;
        // Mikrofony i interfejsy (także wirtualne, np. z odszumianiem) oraz głośniki/słuchawki
        const bool in = std::strncmp(cls, "Audio/Source", 12) == 0, out = std::strcmp(cls, "Audio/Sink") == 0;
        if (!in && !out)
            return;
        AudioDevice dev;
        dev.id = id;
        dev.input = in;
        dev.name = QString::fromUtf8(spa_dict_lookup(props, PW_KEY_NODE_NAME));
        const char *label = spa_dict_lookup(props, PW_KEY_NODE_DESCRIPTION);
        if (!label)
            label = spa_dict_lookup(props, PW_KEY_NODE_NICK);
        dev.label = label ? QString::fromUtf8(label) : dev.name;
        auto *e = static_cast<Engine *>(d);
        {
            QMutexLocker lock(&e->m_devMutex);
            e->m_devices.append(dev);
        }
        QMetaObject::invokeMethod(e, [e] { emit e->devicesChanged(); }, Qt::QueuedConnection);
    }
    static void globalRemove(void *d, uint32_t id)
    {
        auto *e = static_cast<Engine *>(d);
        bool removed;
        {
            QMutexLocker lock(&e->m_devMutex);
            removed = e->m_devices.removeIf([id](const AudioDevice &dev) { return dev.id == id; }) > 0;
        }
        if (removed)
            QMetaObject::invokeMethod(e, [e] { emit e->devicesChanged(); }, Qt::QueuedConnection);
    }
};

static const pw_stream_events s_outEvents = {
    .version = PW_VERSION_STREAM_EVENTS,
    .state_changed = EngineCallbacks::stateChanged,
    .process = EngineCallbacks::outProcess,
};
static const pw_stream_events s_inEvents = {
    .version = PW_VERSION_STREAM_EVENTS,
    .state_changed = EngineCallbacks::stateChanged,
    .process = EngineCallbacks::inProcess,
};
static const pw_registry_events s_registryEvents = {
    .version = PW_VERSION_REGISTRY_EVENTS,
    .global = EngineCallbacks::global,
    .global_remove = EngineCallbacks::globalRemove,
};

static inline EngineHooks *hooks(void *p) { return static_cast<EngineHooks *>(p); }

Engine::Engine(QObject *parent) : QObject(parent)
{
    m_renderer.setLive(&m_live);
    m_hooks = new EngineHooks;
}

Engine::~Engine()
{
    if (m_recThread.joinable()) {
        long long dummy;
        stopRecording(&dummy);
    }
    if (m_loop) {
        pw_thread_loop_lock(m_loop);
        if (m_out) {
            spa_hook_remove(&hooks(m_hooks)->out);
            pw_stream_destroy(m_out);
        }
        if (m_in) {
            spa_hook_remove(&hooks(m_hooks)->in);
            pw_stream_destroy(m_in);
        }
        if (m_registry) {
            spa_hook_remove(&hooks(m_hooks)->registry);
            pw_proxy_destroy(reinterpret_cast<pw_proxy *>(m_registry));
        }
        if (m_core)
            pw_core_disconnect(m_core);
        pw_thread_loop_unlock(m_loop);
        pw_thread_loop_stop(m_loop);
        if (m_context)
            pw_context_destroy(m_context);
        pw_thread_loop_destroy(m_loop);
    }
    collect();
    delete m_current;
    delete m_next.load();
    delete hooks(m_hooks);
}

bool Engine::start()
{
    pw_init(nullptr, nullptr);
    m_loop = pw_thread_loop_new("aster-studio", nullptr);
    m_context = m_loop ? pw_context_new(pw_thread_loop_get_loop(m_loop), nullptr, 0) : nullptr;
    if (!m_context || pw_thread_loop_start(m_loop) < 0) {
        m_error = QStringLiteral("Nie udało się uruchomić dźwięku.");
        return false;
    }
    pw_thread_loop_lock(m_loop);
    m_core = pw_context_connect(m_context, nullptr, 0);
    if (!m_core) {
        pw_thread_loop_unlock(m_loop);
        m_error = QStringLiteral("Brak połączenia z serwerem dźwięku (PipeWire).");
        return false;
    }
    m_registry = pw_core_get_registry(m_core, PW_VERSION_REGISTRY, 0);
    pw_registry_add_listener(m_registry, &hooks(m_hooks)->registry, &s_registryEvents, this);
    connectOutput();
    pw_thread_loop_unlock(m_loop);
    return true;
}

static const spa_pod *stereoFormat(spa_pod_builder *b)
{
    spa_audio_info_raw info{};
    info.format = SPA_AUDIO_FORMAT_F32;
    info.rate = Engine::Rate;
    info.channels = 2;
    info.position[0] = SPA_AUDIO_CHANNEL_FL;
    info.position[1] = SPA_AUDIO_CHANNEL_FR;
    return spa_format_audio_raw_build(b, SPA_PARAM_EnumFormat, &info);
}

// Wołane pod blokadą pętli PipeWire
void Engine::connectOutput()
{
    if (m_out) {
        spa_hook_remove(&hooks(m_hooks)->out);
        pw_stream_destroy(m_out);
        m_out = nullptr;
    }
    pw_properties *props = pw_properties_new(PW_KEY_MEDIA_TYPE, "Audio", PW_KEY_MEDIA_CATEGORY, "Playback",
                                             PW_KEY_MEDIA_ROLE, "Production", PW_KEY_NODE_LATENCY, "256/48000",
                                             PW_KEY_NODE_NAME, "aster-studio", PW_KEY_APP_NAME, "Studio", nullptr);
    if (!m_outName.isEmpty())
        pw_properties_set(props, PW_KEY_TARGET_OBJECT, m_outName.toUtf8().constData());
    m_out = pw_stream_new(m_core, "Studio — odtwarzanie", props);
    pw_stream_add_listener(m_out, &hooks(m_hooks)->out, &s_outEvents, this);
    uint8_t buf[1024];
    spa_pod_builder b = SPA_POD_BUILDER_INIT(buf, sizeof buf);
    const spa_pod *params[1] = {stereoFormat(&b)};
    pw_stream_connect(m_out, PW_DIRECTION_OUTPUT, PW_ID_ANY,
                      pw_stream_flags(PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_MAP_BUFFERS | PW_STREAM_FLAG_RT_PROCESS), params, 1);
}

void Engine::connectInput()
{
    if (m_in) {
        spa_hook_remove(&hooks(m_hooks)->in);
        pw_stream_destroy(m_in);
        m_in = nullptr;
    }
    pw_properties *props = pw_properties_new(PW_KEY_MEDIA_TYPE, "Audio", PW_KEY_MEDIA_CATEGORY, "Capture",
                                             PW_KEY_MEDIA_ROLE, "Production", PW_KEY_NODE_LATENCY, "256/48000",
                                             PW_KEY_NODE_NAME, "aster-studio-input", PW_KEY_APP_NAME, "Studio", nullptr);
    if (!m_inName.isEmpty())
        pw_properties_set(props, PW_KEY_TARGET_OBJECT, m_inName.toUtf8().constData());
    m_in = pw_stream_new(m_core, "Studio — nagrywanie", props);
    pw_stream_add_listener(m_in, &hooks(m_hooks)->in, &s_inEvents, this);
    uint8_t buf[1024];
    spa_pod_builder b = SPA_POD_BUILDER_INIT(buf, sizeof buf);
    const spa_pod *params[1] = {stereoFormat(&b)};
    pw_stream_connect(m_in, PW_DIRECTION_INPUT, PW_ID_ANY,
                      pw_stream_flags(PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_MAP_BUFFERS | PW_STREAM_FLAG_RT_PROCESS), params, 1);
}

void Engine::setMonitor(int track, int channel)
{
    // Bufora nie czyścimy stąd (czyta go tylko wątek wyjścia) — sam odrzuca nadmiar
    m_monChannel.store(channel, std::memory_order_relaxed);
    m_monTrack.store(track, std::memory_order_relaxed);
}

void Engine::setCapture(bool on)
{
    if (!m_core || on == (m_in != nullptr))
        return;
    pw_thread_loop_lock(m_loop);
    if (on) {
        connectInput();
    } else {
        spa_hook_remove(&hooks(m_hooks)->in);
        pw_stream_destroy(m_in);
        m_in = nullptr;
    }
    pw_thread_loop_unlock(m_loop);
    m_inPeak[0].store(0);
    m_inPeak[1].store(0);
}

void Engine::setOutput(const QString &name)
{
    if (name == m_outName)
        return;
    m_outName = name;
    if (!m_core)
        return;
    pw_thread_loop_lock(m_loop);
    connectOutput();
    pw_thread_loop_unlock(m_loop);
}

void Engine::setInput(const QString &name)
{
    if (name == m_inName)
        return;
    m_inName = name;
    if (!m_core || !m_in)
        return;
    pw_thread_loop_lock(m_loop);
    connectInput();
    pw_thread_loop_unlock(m_loop);
}

QList<AudioDevice> Engine::devices() const
{
    QMutexLocker lock(&m_devMutex);
    return m_devices;
}

// ——— Wątek audio ———

void Engine::onPlayback()
{
    pw_buffer *b = pw_stream_dequeue_buffer(m_out);
    if (!b)
        return;
    spa_buffer *buf = b->buffer;
    auto *dst = static_cast<float *>(buf->datas[0].data);
    if (!dst) {
        pw_stream_queue_buffer(m_out, b);
        return;
    }
    constexpr uint32_t stride = 2 * sizeof(float);
    uint32_t n = buf->datas[0].maxsize / stride;
    if (b->requested && b->requested < n)
        n = uint32_t(b->requested);

    // Nowa migawka projektu; poprzednia wraca do wątku interfejsu
    if (Snapshot *s = m_next.exchange(nullptr)) {
        if (m_current) {
            const unsigned w = m_retiredW.load(std::memory_order_relaxed);
            if (w - m_retiredR.load(std::memory_order_acquire) < 64) {
                m_retired[w % 64] = m_current;
                m_retiredW.store(w + 1, std::memory_order_release);
            }
        }
        m_current = s;
    }
    const long long seek = m_seek.exchange(NoSeek);
    if (seek != NoSeek)
        m_rtPos = seek;

    takeLiveCommands();
    // Odsłuch: to, co przyszło z mikrofonu. Nadmiar ponad jeden blok i trochę zapasu — odrzucony,
    // żeby opóźnienie nie rosło; brak — cisza (wejście jeszcze nie ruszyło)
    const int monTrack = m_monTrack.load(std::memory_order_relaxed);
    if (monTrack >= 0) {
        const size_t want = std::min<size_t>(n, m_monBuf.size());
        size_t avail = m_monRing.available();
        while (avail > want + 512) {
            const size_t drop = std::min(avail - want, m_monBuf.size());
            m_monRing.read(m_monBuf.data(), drop);
            avail -= drop;
        }
        const size_t got = m_monRing.read(m_monBuf.data(), std::min(want, avail));
        std::fill(m_monBuf.begin() + long(got), m_monBuf.begin() + long(want), 0.f);
        m_renderer.setMonitor(monTrack, m_monBuf.data(), int(want));
    } else {
        m_renderer.setMonitor(-1, nullptr, 0);
    }
    if (m_playing.load()) {
        const long long cie = m_countInEnd.load();
        const bool click = m_metronome.load() || (cie != NoSeek && m_rtPos < cie);
        // Region pętli: po dojściu do końca wracamy na początek (w środku bloku, bez przerwy).
        // W trakcie nagrywania też — każde przejście to kolejne podejście (nagranie leci ciągiem)
        const bool cycle = m_cycle.load();
        const long long cs = m_cycleStart.load(), ce = m_cycleEnd.load();
        uint32_t done = 0;
        while (done < n) {
            long long k = n - done;
            if (cycle && ce > cs && m_rtPos < ce && m_rtPos + k > ce)
                k = ce - m_rtPos;
            m_renderer.process(m_current, m_rtPos, int(k), dst + 2 * done, click, &m_meters, Rate);
            m_rtPos += k;
            done += uint32_t(k);
            if (cycle && ce > cs && m_rtPos == ce)
                m_rtPos = cs;
        }
    } else {
        // Zatrzymany: mikser bez klipów — granie na żywo z efektami ścieżki i wybrzmiewanie pogłosu/echa
        m_renderer.process(m_current, m_rtPos, int(n), dst, false, &m_meters, Rate, false);
    }
    // Głosy odsłuchu dokładane na wierzch
    for (PreviewSlot &v : m_preview) {
        const unsigned gen = v.gen.load(std::memory_order_acquire);
        if (gen != v.seen) {
            v.seen = gen;
            v.pos = 0;
        }
        const AudioSource *src = v.src.load(std::memory_order_acquire);
        if (!src || v.pos >= src->frames)
            continue;
        const float g = v.gain.load(std::memory_order_relaxed);
        const long long k = std::min<long long>(n, src->frames - v.pos);
        for (long long i = 0; i < k; ++i) {
            dst[2 * i] += src->at(v.pos + i, 0) * g;
            dst[2 * i + 1] += src->at(v.pos + i, 1) * g;
        }
        v.pos += k;
    }
    m_pos.store(m_rtPos);

    pw_time t{};
    if (pw_stream_get_time_n(m_out, &t, sizeof t) == 0 && t.rate.denom)
        m_outDelay.store(t.delay * Rate * t.rate.num / t.rate.denom);

    buf->datas[0].chunk->offset = 0;
    buf->datas[0].chunk->stride = stride;
    buf->datas[0].chunk->size = n * stride;
    pw_stream_queue_buffer(m_out, b);
}

void Engine::onCapture()
{
    pw_buffer *b = pw_stream_dequeue_buffer(m_in);
    if (!b)
        return;
    spa_data &d = b->buffer->datas[0];
    if (d.data) {
        const auto *src = reinterpret_cast<const float *>(static_cast<const uint8_t *>(d.data) + d.chunk->offset);
        const uint32_t n = d.chunk->size / (2 * sizeof(float));
        float pl = 0.f, pr = 0.f;
        for (uint32_t i = 0; i < n; ++i) {
            pl = std::max(pl, std::fabs(src[2 * i]));
            pr = std::max(pr, std::fabs(src[2 * i + 1]));
        }
        raisePeak(m_inPeak[0], pl);
        raisePeak(m_inPeak[1], pr);
        if (m_monTrack.load(std::memory_order_relaxed) >= 0) {
            const int ch = m_monChannel.load(std::memory_order_relaxed);
            float mono[256];
            for (uint32_t i = 0; i < n;) {
                const uint32_t k = std::min<uint32_t>(256, n - i);
                for (uint32_t j = 0; j < k; ++j) {
                    const float l = src[2 * (i + j)], r = src[2 * (i + j) + 1];
                    mono[j] = ch == 1 ? l : ch == 2 ? r : 0.5f * (l + r);
                }
                m_monRing.write(mono, k);
                i += k;
            }
        }
        if (m_recActive.load() && m_playing.load()) {
            // Miejsce na osi czasu: to, co muzyk słyszał, gdy grał — po odjęciu opóźnienia wyjścia i wejścia
            if (m_recFirst.load() == NoSeek) {
                pw_time t{};
                long long inDelay = 0;
                if (pw_stream_get_time_n(m_in, &t, sizeof t) == 0 && t.rate.denom)
                    inDelay = t.delay * Rate * t.rate.num / t.rate.denom;
                m_recFirst.store(m_pos.load() - m_outDelay.load() - inDelay - n - m_extraLatency.load());
            }
            m_ring.write(src, size_t(n) * 2);
        }
    }
    pw_stream_queue_buffer(m_in, b);
}

// ——— Interfejs → silnik ———

void Engine::preview(SourcePtr sound, float gain)
{
    if (!sound || !m_core)
        return;
    // Dźwięki starsze niż 10 s na pewno już przebrzmiały — można je zwolnić
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    while (!m_previewKeep.isEmpty() && now - m_previewKeep.first().first > 10000)
        m_previewKeep.removeFirst();
    m_previewKeep.append({now, sound});
    PreviewSlot &v = m_preview[m_previewNext];
    m_previewNext = (m_previewNext + 1) % PreviewVoices;
    v.gain.store(gain);
    v.src.store(sound.get(), std::memory_order_release);
    v.gen.fetch_add(1, std::memory_order_acq_rel);
}

void Engine::pushLive(const LiveCmd &c)
{
    if (!m_core)
        return;
    const unsigned w = m_liveW.load(std::memory_order_relaxed);
    if (w - m_liveR.load(std::memory_order_acquire) >= LiveQueue)
        return;                                 // kolejka pełna (nie powinno się zdarzyć) — nutę pomijamy
    m_liveCmds[w % LiveQueue] = c;
    m_liveW.store(w + 1, std::memory_order_release);
}

void Engine::liveNoteOn(int id, int track, SynthVoice::Inst inst, double freq, float gain)
{
    pushLive({id, track, int(inst), float(freq), gain, true});
}

void Engine::liveNoteOff(int id)
{
    pushLive({id, 0, 0, 0, 0, false});
}

void Engine::takeLiveCommands()
{
    unsigned r = m_liveR.load(std::memory_order_relaxed);
    const unsigned w = m_liveW.load(std::memory_order_acquire);
    for (; r != w; ++r) {
        const LiveCmd &c = m_liveCmds[r % LiveQueue];
        if (c.on)
            m_live.noteOn(c.id, c.track, SynthVoice::Inst(c.inst), c.freq, Rate, c.gain);
        else
            m_live.noteOff(c.id);
    }
    m_liveR.store(r, std::memory_order_release);
}

void Engine::setSnapshot(Snapshot *s)
{
    if (!m_core) {
        m_offline.reset(s);
        return;
    }
    delete m_next.exchange(s);       // poprzednia, której wątek audio nie zdążył wziąć
}

void Engine::collect()
{
    unsigned r = m_retiredR.load(std::memory_order_relaxed);
    const unsigned w = m_retiredW.load(std::memory_order_acquire);
    while (r != w) {
        delete m_retired[r % 64];
        m_retired[r % 64] = nullptr;
        ++r;
    }
    m_retiredR.store(r, std::memory_order_release);
}

void Engine::play(long long from, long long countInEnd)
{
    m_countInEnd.store(countInEnd);
    m_seek.store(from);
    m_pos.store(from);
    m_playing.store(true);
}

void Engine::setCycle(bool on, long long start, long long end)
{
    m_cycleStart.store(start);
    m_cycleEnd.store(end);
    m_cycle.store(on);
}

void Engine::stop()
{
    m_playing.store(false);
    m_countInEnd.store(NoSeek);
}

void Engine::seek(long long frame)
{
    m_seek.store(frame);
    m_pos.store(frame);
    if (!m_core)
        m_rtPos = frame;
}

long long Engine::position() const
{
    return m_pos.load();
}

void Engine::readMeters(std::vector<float> &tracks, float master[2])
{
    for (size_t i = 0; i < tracks.size() && i < size_t(Renderer::MaxTracks); ++i)
        tracks[i] = std::max(m_meters[i][0].exchange(0.f), m_meters[i][1].exchange(0.f));
    master[0] = m_meters[Renderer::MaxTracks][0].exchange(0.f);
    master[1] = m_meters[Renderer::MaxTracks][1].exchange(0.f);
}

void Engine::readInputLevel(float level[2])
{
    level[0] = m_inPeak[0].exchange(0.f);
    level[1] = m_inPeak[1].exchange(0.f);
}

// ——— Nagrywanie ———

bool Engine::startRecording(const QString &path, long long start, int channel)
{
    if (!m_in || m_recThread.joinable())
        return false;
    m_ring.clear();
    m_recFirst.store(NoSeek);
    m_recStart = start;
    m_recClipStart.store(start);
    m_recData.clear();
    {
        QMutexLocker lock(&m_liveMutex);
        m_livePeaks.clear();
    }
    m_recStop.store(false);
    m_recThread = std::thread(&Engine::writerLoop, this, path, channel);
    m_recActive.store(true);
    return true;
}

void Engine::writerLoop(QString path, int channel)
{
    SF_INFO info{};
    info.samplerate = Rate;
    info.channels = 1;
    info.format = SF_FORMAT_WAV | SF_FORMAT_PCM_24;
    SNDFILE *sf = sf_open(QFile::encodeName(path).constData(), SFM_WRITE, &info);
    std::vector<float> buf(8192), mono;
    mono.reserve(4096);
    long long seen = 0;             // ramki odebrane od początku nagrania
    float lo = 0.f, hi = 0.f;
    int inPeak = 0;
    bool started = false;
    for (;;) {
        const bool stopping = m_recStop.load();
        const size_t want = std::min(buf.size(), m_ring.available() & ~size_t(1));
        const size_t got = want ? m_ring.read(buf.data(), want) : 0;
        if (got == 0) {
            if (stopping)
                break;
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
            continue;
        }
        const long long first = m_recFirst.load();
        mono.clear();
        std::vector<float> peaks;
        for (size_t i = 0; i + 1 < got; i += 2, ++seen) {
            const long long pos = first + seen;
            if (pos < m_recStart)
                continue;               // odliczanie — nie nagrywamy
            if (!started) {
                m_recClipStart.store(pos);
                started = true;
            }
            const float v = channel == 1 ? buf[i] : channel == 2 ? buf[i + 1] : 0.5f * (buf[i] + buf[i + 1]);
            mono.push_back(v);
            lo = std::min(lo, v);
            hi = std::max(hi, v);
            if (++inPeak == AudioSource::PeakStep) {
                peaks.push_back(lo);
                peaks.push_back(hi);
                lo = hi = 0.f;
                inPeak = 0;
            }
        }
        if (mono.empty())
            continue;
        if (sf)
            sf_writef_float(sf, mono.data(), sf_count_t(mono.size()));
        m_recData.insert(m_recData.end(), mono.begin(), mono.end());
        if (!peaks.empty()) {
            QMutexLocker lock(&m_liveMutex);
            m_livePeaks.insert(m_livePeaks.end(), peaks.begin(), peaks.end());
        }
    }
    if (sf)
        sf_close(sf);
}

std::shared_ptr<AudioSource> Engine::stopRecording(long long *start)
{
    if (!m_recThread.joinable())
        return {};
    m_recActive.store(false);
    m_recStop.store(true);
    m_recThread.join();
    *start = m_recClipStart.load();
    if (m_recData.empty())
        return {};
    auto src = std::make_shared<AudioSource>();
    src->channels = 1;
    src->data = std::move(m_recData);
    src->frames = (long long)src->data.size();
    src->computePeaks();
    m_recData = {};
    return src;
}

long long Engine::recordedFrames() const
{
    QMutexLocker lock(&m_liveMutex);
    return (long long)(m_livePeaks.size() / 2) * AudioSource::PeakStep;
}

std::vector<float> Engine::livePeaks() const
{
    QMutexLocker lock(&m_liveMutex);
    return m_livePeaks;
}

// ——— Eksport ———

bool Engine::exportMix(const Snapshot &s, long long frames, const QString &path, const QString &format,
                       const std::function<bool(double)> &progress, QString *error)
{
    SF_INFO info{};
    info.samplerate = Rate;
    info.channels = 2;
    if (format == QLatin1String("mp3"))
        info.format = SF_FORMAT_MPEG | SF_FORMAT_MPEG_LAYER_III;
    else if (format == QLatin1String("ogg"))
        info.format = SF_FORMAT_OGG | SF_FORMAT_VORBIS;
    else if (format == QLatin1String("flac"))
        info.format = SF_FORMAT_FLAC | SF_FORMAT_PCM_24;
    else
        info.format = SF_FORMAT_WAV | SF_FORMAT_PCM_16;
    SNDFILE *sf = sf_open(QFile::encodeName(path).constData(), SFM_WRITE, &info);
    if (!sf) {
        if (error)
            *error = QString::fromUtf8(sf_strerror(nullptr));
        return false;
    }
    if (format == QLatin1String("mp3")) {
        int mode = SF_BITRATE_MODE_VARIABLE;
        sf_command(sf, SFC_SET_BITRATE_MODE, &mode, sizeof mode);
    }
    if (format == QLatin1String("mp3") || format == QLatin1String("ogg")) {
        double level = 0.25;        // wysoka jakość (0 = najlepsza, 1 = najmniejszy plik)
        sf_command(sf, SFC_SET_COMPRESSION_LEVEL, &level, sizeof level);
    }
    sf_command(sf, SFC_SET_CLIPPING, nullptr, SF_TRUE);

    auto renderer = std::make_unique<Renderer>();
    if (format == QLatin1String("mp3") || format == QLatin1String("ogg"))
        renderer->setCeiling(0.84f);        // −1,5 dBFS
    std::vector<float> buf(size_t(Renderer::MaxBlock) * 2);
    bool ok = true;
    for (long long pos = 0; pos < frames; pos += Renderer::MaxBlock) {
        const int n = int(std::min<long long>(Renderer::MaxBlock, frames - pos));
        renderer->process(&s, pos, n, buf.data(), false, nullptr, Rate);
        for (int i = 0; i < 2 * n; ++i)
            buf[size_t(i)] = std::clamp(buf[size_t(i)], -1.f, 1.f);
        if (sf_writef_float(sf, buf.data(), n) != n) {
            if (error)
                *error = QString::fromUtf8(sf_strerror(sf));
            ok = false;
            break;
        }
        if (progress && (pos / Renderer::MaxBlock) % 64 == 0 && !progress(double(pos) / frames)) {
            ok = false;
            break;
        }
    }
    sf_close(sf);
    if (!ok)
        QFile::remove(path);
    return ok;
}
